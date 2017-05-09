#!/usr/bin/perl
use strict;
use warnings;

use OESS::Database;
use OESS::Circuit;

use XML::Simple;
use Log::Log4perl;
use FindBin;
use Fcntl qw(:flock);
use Data::Dumper;

use GRNOC::RabbitMQ::Client;

sub main{
    Log::Log4perl::init('/etc/oess/logging.conf');
    my $logger = Log::Log4perl->get_logger('OESS.Scheduler');

    $logger->info("INFO Running OESS Scheduler.");

    my $time = time();

    my $oess = OESS::Database->new();
    my $rabbit_host = $oess->{'configuration'}->{'rabbitMQ'}->{'host'};
    my $rabbit_port = $oess->{'configuration'}->{'rabbitMQ'}->{'port'};
    my $rabbit_user = $oess->{'configuration'}->{'rabbitMQ'}->{'user'};
    my $rabbit_pass = $oess->{'configuration'}->{'rabbitMQ'}->{'pass'};

    my $client  = new GRNOC::RabbitMQ::Client(
        exchange => 'OESS',
	topic => 'OF.FWDCTL.RPC',
	host => $rabbit_host,
	port => $rabbit_port,
        user => $rabbit_user,
        pass => $rabbit_pass,
	timeout => 15
    );

    if ( !defined($client) ) {
	$logger->error("Couldn't connect to RabbitMQ.");
        return;
    }

    my $actions = $oess->get_current_actions();
    $logger->debug("Executing scheduled actions: " . Dumper($actions));

    foreach my $action (@$actions){
        my $ckt = $oess->get_circuit_by_id( circuit_id => $action->{'circuit_id'})->[0];
        my $circuit_layout = XMLin($action->{'circuit_layout'}, forcearray => 1);

	$logger->info("Scheduling $circuit_layout->{'action'} for circuit_id $action->{'circuit_id'}.");

	if ($ckt->{'type'} eq 'openflow') {
	    $client->{'topic'} = 'OF.FWDCTL.RPC';
	} else {
	    $client->{'topic'} = 'MPLS.FWDCTL.RPC';
	}

        if($circuit_layout->{'action'} eq 'provision'){

            if($ckt->{'circuit_state'} eq 'reserved'){
                #if the circuit goes into provisioned state, we'll execute...
                next;
            }

            if($ckt->{'circuit_state'} eq 'decom'){
                $oess->update_action_complete_epoch( scheduled_action_id => $action->{'scheduled_action_id'});
                #circuit is decom remove from queue!
                next;
            }

	    $logger->info("Circuit " . $circuit_layout->{'name'} . ":" . $circuit_layout->{'circuit_id'} . " scheduled for activation NOW!");
            my $user = $oess->get_user_by_id( user_id => $action->{'user_id'} )->[0];


            #edit the circuit to make it active
            my $output = $oess->edit_circuit(
		circuit_id     => $action->{'circuit_id'},
		static_mac     => $circuit_layout->{'static_mac'},
		endpoint_mac_address_nums => $circuit_layout->{'endpoint_mac_address_nums'},
		mac_addresses  => $circuit_layout->{'mac_addresses'},
		name           => $circuit_layout->{'name'},
		bandwidth      => $circuit_layout->{'bandwidth'},
		provision_time => time(),
		remove_time    => $circuit_layout->{'remove_time'},
		restore_to_primary => $circuit_layout->{'restore_to_primary'},
		links          => $circuit_layout->{'links'},
		backup_links   => $circuit_layout->{'backup_links'},
		nodes          => $circuit_layout->{'nodes'},
		interfaces     => $circuit_layout->{'interfaces'},
		tags           => $circuit_layout->{'tags'},
		state          => 'active',
		user_name      => $user->{'auth_name'},
		workgroup_id   => $action->{'workgroup_id'},
		description    => $ckt->{'description'},
		type           => $ckt->{'type'}
	    );
            if (!defined $output) {
		$logger->warn("Failed to update database to provision circuit: " . $oess->get_error());
            }

            my $res;
            my $result;
            my $event_id;
            eval {
                $result = AnyEvent->condvar;

                $client->addVlan(
                    circuit_id => int($action->{'circuit_id'}),
                    async_callback => sub {
                        my $r = shift;
                        $result->send($r);
                    }
                );

                my $final_res = $result->recv();
                if (defined $final_res->{'error'}) {
		    $logger->error("Circuit " . $action->{'circuit_id'} . " couldn't be added: " . $final_res->{'error'});
                    return;
                }

                $res = $final_res;
            };

            $oess->update_action_complete_epoch( scheduled_action_id => $action->{'scheduled_action_id'});
            

            #--- signal fwdctl to update caches
            eval{
                $result = AnyEvent->condvar;

                $client->update_cache(
                    circuit_id => int($action->{'circuit_id'}),
                    async_callback => sub {
                        my $r = shift;
                        $result->send($r);
                    }
                );

                my $update_cache_result = $result->recv();
                if (defined $update_cache_result->{'error'}) {
		    $logger->error("Cache update error for " . $action->{'circuit_id'} . ":" . $circuit_layout->{'circuit_id'} . ".");
                    return;
                }

                $res = $update_cache_result;
            };

            eval {
                my $circuit_details = $oess->get_circuit_details( circuit_id => $action->{'circuit_id'} );
                $circuit_details->{'status'} = 'up';
                $circuit_details->{'type'} = 'provisioned';
                $circuit_details->{'reason'} = ' scheduled circuit provisioning';
                $client->{'topic'} = 'OF.FWDCTL.event';
                $client->circuit_notification(type      => 'provisioned',
                                              link_name => 'n/a',
                                              affected_circuits => [$circuit_details],
                                              no_reply  => 1);
		$client->{'topic'} = 'OF.FWCTL';
            };
            
            
        } elsif($circuit_layout->{'action'} eq 'edit'){
	    $logger->info("Circuit " . $circuit_layout->{'name'} . ":" . $circuit_layout->{'circuit_id'} . " scheduled for edit NOW!");
            my $res;
            my $result;
            my $event_id;
            eval {
                $result = AnyEvent->condvar;

                $client->deleteVlan(
                    circuit_id => int($action->{'circuit_id'}),
                    async_callback => sub {
                        my $r = shift;
                        $result->send($r);
                    }
                );

                my $final_res = $result->recv();
                if (defined $final_res->{'error'}) {
		    $logger->error("deleteVlan failed for " . $action->{'circuit_id'} . ":" . $circuit_layout->{'circuit_id'} . ".");
                }

                $res = $final_res;
            };
            
            #same as provision
            if($ckt->{'circuit_state'} eq 'reserved'){
                #if the circuit goes into provisioned state, we'll execute...
                next;
            }

            if($ckt->{'circuit_state'} eq 'decom'){
                $oess->update_action_complete_epoch( scheduled_action_id => $action->{'scheduled_action_id'});
                #circuit is decom remove from queue!
            }

            my $user = $oess->get_user_by_id( user_id => $action->{'user_id'} )->[0];

	    $logger->info("Circuit info: " . Dumper($circuit_layout));

            my $output = $oess->edit_circuit(circuit_id     => $action->{'circuit_id'},
                                             static_mac     => $circuit_layout->{'static_mac'},
                                             endpoint_mac_address_nums => $circuit_layout->{'endpoint_mac_address_nums'},
                                             mac_addresses  => $circuit_layout->{'mac_addresses'},
                                             name           => $circuit_layout->{'name'},
                                             bandwidth      => $circuit_layout->{'bandwidth'},
                                             provision_time => time(),
                                             remove_time    => $circuit_layout->{'remove_time'},
                                             restore_to_primary => $circuit_layout->{'restore_to_primary'},
                                             links          => $circuit_layout->{'links'},
                                             backup_links   => $circuit_layout->{'backup_links'},
                                             nodes          => $circuit_layout->{'nodes'},
                                             interfaces     => $circuit_layout->{'interfaces'},
                                             tags           => $circuit_layout->{'tags'},
                                             state          => $circuit_layout->{'state'},
                                             user_name      => $user->{'auth_name'},
                                             workgroup_id   => $action->{'workgroup_id'},
                                             description    => $ckt->{'description'}
                );
            if (!defined $output) {
		$logger->info("Failed to update database with new circuit parameters: " . $oess->get_error());
            }
            
            $res = undef;
            $result = undef;
            $event_id = undef;;
            eval{
                if($circuit_layout->{'state'} eq 'active'){
                    $result = AnyEvent->condvar;

                    $client->addVlan(
                        circuit_id => int($action->{'circuit_id'}),
                        async_callback => sub {
                            my $r = shift;
                            $result->send($r);
                        }
                    );

                    my $final_res = $result->recv();
                    if (defined $final_res->{'error'}) {
			$logger->error("Circuit " . $action->{'circuit_id'} . ":" . $circuit_layout->{'circuit_id'} . " couldn't be added.");
                        return;
                    }

                    $res = $final_res;
                }
            };
            
            $oess->update_action_complete_epoch( scheduled_action_id => $action->{'scheduled_action_id'});
            
            #--- signal fwdctl to update caches
            eval{
                $result = AnyEvent->condvar;

                $client->update_cache(
                    circuit_id => int($action->{'circuit_id'}),
                    async_callback => sub {
                        my $r = shift;
                        $result->send($r);
                    }
                );

                my $update_cache_result = $result->recv();
                if (defined $update_cache_result->{'error'}) {
                    $logger->error("Cache update error for " . $action->{'circuit_id'} . ":" . $circuit_layout->{'circuit_id'} . ".");
                    return;
                }

                $res = $update_cache_result;
            };

            if(!defined $res){
                $logger->error("Error updating cache after scheduled vlan removal.");
            }

            eval{
                my $circuit_details = $oess->get_circuit_details( circuit_id => $action->{'circuit_id'} );
                $circuit_details->{'status'} = 'up';
                $circuit_details->{'type'} = 'modified';
                $circuit_details->{'reason'} = ' scheduled circuit modification';
                $client->{'topic'} = 'OF.FWDCTL.event';
                $client->circuit_notification(type      => 'modified',
                                              link_name => 'n/a',
                                              affected_circuits => [$circuit_details],
                                              no_reply  => 1);
		$client->{'topic'} = 'OF.FWDCTL.RPC';
            };

        }
        elsif($circuit_layout->{'action'} eq 'remove'){
            $logger->error("Circuit " . $circuit_layout->{'name'} . ":" . $action->{'circuit_id'} . " scheduled for removal NOW!");
            my $res;
            my $result;
            my $event_id;
            eval{
                $result = AnyEvent->condvar;

                $client->deleteVlan(
                    circuit_id => int($action->{'circuit_id'}),
                    async_callback => sub {
                        my $r = shift;
                        $result->send($r);
                    }
                );

                my $final_res = $result->recv();
                if (defined $final_res->{'error'}) {
                    $logger->error("deleteVlan failed for " . $action->{'circuit_id'} . ":" . $circuit_layout->{'circuit_id'} . ".");
                }

                $res = $final_res;
            };
            
            if(!defined($res)){
                $logger->error("Res was not defined");
            }
            
            my $user = $oess->get_user_by_id( user_id => $action->{'user_id'} )->[0];
            $res = $oess->remove_circuit( circuit_id => $action->{'circuit_id'}, remove_time => time(), username => $user->{'auth_name'});
            
            
            if(!defined($res)){
                $logger->error("unable to remove circuit");
                $oess->_rollback();
                die;
            }else{
                
                $res = $oess->update_action_complete_epoch( scheduled_action_id => $action->{'scheduled_action_id'});
                
                
                if(!defined($res)){
                    $logger->error("Unable to complete action");
                    $oess->_rollback();
                }
            }

            #--- signal fwdctl to update caches
            eval{
                my $result = AnyEvent->condvar;

                $client->update_cache(
                    circuit_id => int($action->{'circuit_id'}),
                    async_callback => sub {
                        my $r = shift;
                        $result->send($r);
                    }
                );

                my $update_cache_result = $result->recv();
                if (defined $update_cache_result->{'error'}) {
                    $logger->error("Cache update error for " . $action->{'circuit_id'} . ":" . $circuit_layout->{'circuit_id'} . ".");
                    return;
                }

                $res = $update_cache_result;
            };

            #Delete is complete and successful, send event to Rabbit
            eval {
                $logger->debug("sending circuit decommission");
                my $circuit_details = $oess->get_circuit_details( circuit_id => $action->{'circuit_id'} );
                $circuit_details->{'status'} = 'removed';
                $circuit_details->{'type'} = 'removed';
                $circuit_details->{'reason'} = ' scheduled circuit removal';
                $client->{'topic'} = 'OF.FWDCTL.event';
                $client->circuit_notification(type      => 'removed',
                                              link_name => 'n/a',
                                              affected_circuits => [$circuit_details],
                                              no_reply  => 1);
		$client->{'topic'} = 'OF.FWCTL';
            };

        }elsif($circuit_layout->{'action'} eq 'change_path'){
            $logger->error("Found a change_path action!!\n");
            #verify the circuit has an alternate path
            my $circuit = OESS::Circuit->new( db=>$oess, circuit_id => $action->{'circuit_id'});
            my $circuit_details = $circuit->{'details'};
            
            #if we are already on our scheduled path... don't change
            if($circuit_details->{'active_path'} ne $circuit_layout->{'path'}){
                $logger->info("Changing the patch of circuit " . $circuit_details->{'description'} . ":" . $circuit_details->{'circuit_id'});
                my $success = $circuit->change_path( user_id => 1, reason => $circuit_layout->{'reason'});
                #my $success = 1;
                my $res;
                my $result;
                my $event_id;
                if($success){
                    eval{
                        my $cv = AnyEvent->condvar;

                        $client->changeVlanPath(
                            circuit_id => $action->{'circuit_id'},
                            async_callback => sub {
                                my $r = shift;
                                $cv->send($r);
                        });
                        
                        my $final_res = $cv->recv();
                        if(defined($result->{'error'})) {
                            $logger->error($result->{'error'});
                            return;
                        }

                        $res = $final_res;
                    };
                }

                $res = $oess->update_action_complete_epoch( scheduled_action_id => $action->{'scheduled_action_id'});

                if(!defined($res)){
                    $logger->error("Unable to complete action");
                    $oess->_rollback();
                }

                eval{
                    my $circuit_details = $oess->get_circuit_details( circuit_id => $action->{'circuit_id'} );
                    $circuit_details->{'status'} = 'up';
                    $circuit_details->{'reason'} = $circuit_layout->{'reason'};
                    $circuit_details->{'type'} = 'change_path';
                    warn "Attempting to send notification\n";
                    $client->{'topic'} = 'OF.FWDCTL.event';
                    $client->circuit_notification(type      => 'change_path',
                                                  link_name => 'n/a',
                                                  affected_circuits => [$circuit_details],
                                                  no_reply  => 1);
		    $client->{'topic'} = 'OF.FWDCTL.RPC';
                }

            }else{
                #already done... nothing to do... complete the scheduled action
                $logger->warn("Circuit " . $circuit_details->{'description'} . ":" . $circuit_details->{'circuit_id'} . " is already on Path:" . $circuit_layout->{'path'} . "completing scheduled action");
                my $res = $oess->update_action_complete_epoch( scheduled_action_id => $action->{'scheduled_action_id'});

                if(!defined($res)){
                    $logger->error("Unable to complete action");
                    $oess->_rollback();
                }
            }
            
        }
    }
}

#before we go into awesome update stuff, lets make sure we aren't already running, by getting a lock on ourself..

open (my $fh, ">>", "$FindBin::RealBin/"."$FindBin::RealScript");

flock($fh,LOCK_EX|LOCK_NB) or die ("Could not get lock, scheduler must still be running");

main();

flock($fh,LOCK_UN);


