#!/usr/bin/perl
use strict;
use warnings;

use OESS::Database;
use OESS::Circuit;

use XML::Simple;
use Sys::Syslog qw(:standard :macros);
use FindBin;
use Fcntl qw(:flock);
use Data::Dumper;

use GRNOC::RabbitMQ::Client;

sub main{
    openlog("oess_scheduler.pl", 'cons,pid', LOG_DAEMON);
    setlogmask( LOG_UPTO(LOG_INFO) );

    syslog(LOG_INFO, "INFO Running OESS Scheduler.");


    my $time = time();

    my $oess = OESS::Database->new();
    my $rabbit_host = $oess->{'configuration'}->{'rabbitMQ'}->{'host'};
    my $rabbit_port = $oess->{'configuration'}->{'rabbitMQ'}->{'port'};
    my $rabbit_user = $oess->{'configuration'}->{'rabbitMQ'}->{'user'};
    my $rabbit_pass = $oess->{'configuration'}->{'rabbitMQ'}->{'pass'};

    my $client  = new GRNOC::RabbitMQ::Client(
        queue => 'OESS-SCHEDULER',
        exchange => 'OESS',
	topic => 'OF.FWDCTL.RPC',
	host => $rabbit_host,
	port => $rabbit_port,
        user => $rabbit_user,
        pass => $rabbit_pass
    );

    if ( !defined($client) ) {
        syslog(LOG_ERR, "Couldn't connect to RabbitMQ.");
        return;
    }


    my $actions = $oess->get_current_actions();

    foreach my $action (@$actions){
        my $ckt = $oess->get_circuit_by_id( circuit_id => $action->{'circuit_id'})->[0];
        my $circuit_layout = XMLin($action->{'circuit_layout'}, forcearray => 1);

        syslog(LOG_INFO, "Scheduling for circuit_id $action->{'circuit_id'}: " . Dumper($circuit_layout));

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

            syslog(LOG_INFO, "Circuit " . $circuit_layout->{'name'} . ":" . $circuit_layout->{'circuit_id'} . " scheduled for activation NOW!");
            my $user = $oess->get_user_by_id( user_id => $action->{'user_id'} )->[0];

            #edit the circuit to make it active
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
                                             state          => 'active',
                                             user_name      => $user->{'auth_name'},
                                             workgroup_id   => $action->{'workgroup_id'},
                                             description    => $ckt->{'description'}
                );
            if (!defined $output) {
                syslog(LOG_WARNING, "Failed to update database to provision circuit: " . $oess->get_error());
            }

            my $res;
            my $result;
            my $event_id;
            eval {
                $result = AnyEvent->condvar;

                $client->addVlan(
                    circuit_id => int($action->{'circuit_id'}),
                    async_callback => sub {
                        my $result = shift;
                        $result->send($result);
                    }
                );

                my $final_res = $result->recv();
                if (defined $final_res->{'error'}) {
                    syslog(LOG_ERR, "Circuit " . $action->{'circuit_id'} . ":" . $circuit_layout->{'circuit_id'} . " couldn't be added.");
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
                        my $result = shift;
                        $result->send($result);
                    }
                );

                my $update_cache_result = $result->recv();
                if (defined $update_cache_result->{'error'}) {
                    syslog(LOG_ERR, "Cache update error for " . $action->{'circuit_id'} . ":" . $circuit_layout->{'circuit_id'} . ".");
                    return;
                }

                $res = $update_cache_result;
            };

            eval {
                my $circuit_details = $oess->get_circuit_details( circuit_id => $action->{'circuit_id'} );
                $circuit_details->{'status'} = 'up';
                $circuit_details->{'type'} = 'provisioned';
                $circuit_details->{'reason'} = ' scheduled circuit provisioning';
		$client->{'topic'} = 'OF.Notification.event';
                $client->circuit_notification( $circuit_details );
		$client->{'topic'} = 'OF.FWCTL';
            };
            
            
        } elsif($circuit_layout->{'action'} eq 'edit'){
            syslog(LOG_INFO, "Circuit " . $circuit_layout->{'name'} . ":" . $circuit_layout->{'circuit_id'} . " scheduled for edit NOW!");
            my $res;
            my $result;
            my $event_id;
            eval {
                $result = AnyEvent->condvar;

                $client->deleteVlan(
                    circuit_id => int($action->{'circuit_id'}),
                    async_callback => sub {
                        my $result = shift;
                        $result->send($result);
                    }
                );

                my $final_res = $result->recv();
                if (defined $final_res->{'error'}) {
                    syslog(LOG_ERR, "deleteVlan failed for " . $action->{'circuit_id'} . ":" . $circuit_layout->{'circuit_id'} . ".");
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

            syslog(LOG_INFO, "Circuit info: " . Dumper($circuit_layout));

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
                syslog(LOG_WARNING, "Failed to update database with new circuit parameters: " . $oess->get_error());
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
                            my $result = shift;
                            $result->send($result);
                        }
                    );

                    my $final_res = $result->recv();
                    if (defined $final_res->{'error'}) {
                        syslog(LOG_ERR, "Circuit " . $action->{'circuit_id'} . ":" . $circuit_layout->{'circuit_id'} . " couldn't be added.");
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
                        my $result = shift;
                        $result->send($result);
                    }
                );

                my $update_cache_result = $result->recv();
                if (defined $update_cache_result->{'error'}) {
                    syslog(LOG_ERR, "Cache update error for " . $action->{'circuit_id'} . ":" . $circuit_layout->{'circuit_id'} . ".");
                    return;
                }

                $res = $update_cache_result;
            };

            if(!defined $res){
                syslog(LOG_ERR, "Error updating cache after scheduled vlan removal.");
            }

            eval{
                my $circuit_details = $oess->get_circuit_details( circuit_id => $action->{'circuit_id'} );
                $circuit_details->{'status'} = 'up';
                $circuit_details->{'type'} = 'modified';
                $circuit_details->{'reason'} = ' scheduled circuit modification';
		$client->{'topic'} = 'OF.Notification.event';
                $client->circuit_notification( $circuit_details );
		$client->{'topic'} = 'OF.FWDCTL.RPC';
            };

        }
        elsif($circuit_layout->{'action'} eq 'remove'){
            syslog(LOG_ERR, "Circuit " . $circuit_layout->{'name'} . ":" . $action->{'circuit_id'} . " scheduled for removal NOW!");
            my $res;
            my $result;
            my $event_id;
            eval{
                $result = AnyEvent->condvar;

                $client->deleteVlan(
                    circuit_id => int($action->{'circuit_id'}),
                    async_callback => sub {
                        my $result = shift;
                        $result->send($result);
                    }
                );

                my $final_res = $result->recv();
                if (defined $final_res->{'error'}) {
                    syslog(LOG_ERR, "deleteVlan failed for " . $action->{'circuit_id'} . ":" . $circuit_layout->{'circuit_id'} . ".");
                }

                $res = $final_res;
            };
            
            if(!defined($res)){
                syslog(LOG_ERR,"Res was not defined");
            }
            
            my $user = $oess->get_user_by_id( user_id => $action->{'user_id'} )->[0];
            $res = $oess->remove_circuit( circuit_id => $action->{'circuit_id'}, remove_time => time(), username => $user->{'auth_name'});
            
            
            if(!defined($res)){
                syslog(LOG_ERR,"unable to remove circuit");
                $oess->_rollback();
                die;
            }else{
                
                $res = $oess->update_action_complete_epoch( scheduled_action_id => $action->{'scheduled_action_id'});
                
                
                if(!defined($res)){
                    syslog(LOG_ERR,"Unable to complete action");
                    $oess->_rollback();
                }
            }

            #--- signal fwdctl to update caches
            eval{
                my $result = AnyEvent->condvar;

                $client->update_cache(
                    circuit_id => int($action->{'circuit_id'}),
                    async_callback => sub {
                        my $result = shift;
                        $result->send($result);
                    }
                );

                my $update_cache_result = $result->recv();
                if (defined $update_cache_result->{'error'}) {
                    syslog(LOG_ERR, "Cache update error for " . $action->{'circuit_id'} . ":" . $circuit_layout->{'circuit_id'} . ".");
                    return;
                }

                $res = $update_cache_result;
            };

            #Delete is complete and successful, send event to Rabbit
            eval {
                syslog(LOG_DEBUG,"sending circuit decommission");
                my $circuit_details = $oess->get_circuit_details( circuit_id => $action->{'circuit_id'} );
                $circuit_details->{'status'} = 'removed';
                $circuit_details->{'type'} = 'removed';
                $circuit_details->{'reason'} = ' scheduled circuit removal';
		$client->{'topic'} = 'OF.Notification.event';
                $client->circuit_notification($circuit_details);
		$client->{'topic'} = 'OF.FWCTL';
            };

        }elsif($circuit_layout->{'action'} eq 'change_path'){
            syslog(LOG_ERR,"Found a change_path action!!\n");
            #verify the circuit has an alternate path
            my $circuit = OESS::Circuit->new( db=>$oess, circuit_id => $action->{'circuit_id'});
            my $circuit_details = $circuit->{'details'};
            
            #if we are already on our scheduled path... don't change
            if($circuit_details->{'active_path'} ne $circuit_layout->{'path'}){
                syslog(LOG_INFO,"Changing the patch of circuit " . $circuit_details->{'description'} . ":" . $circuit_details->{'circuit_id'});
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
                                my $result = shift;
                                $cv->send($result);
                        });
                        
                        my $final_res = $cv->recv();
                        if(defined($result->{'error'})) {
                            syslog(LOG_ERR, $result->{'error'});
                            return;
                        }

                        $res = $final_res;
                    };
                }

                $res = $oess->update_action_complete_epoch( scheduled_action_id => $action->{'scheduled_action_id'});

                if(!defined($res)){
                    syslog(LOG_ERR,"Unable to complete action");
                    $oess->_rollback();
                }

                eval{
                    my $circuit_details = $oess->get_circuit_details( circuit_id => $action->{'circuit_id'} );
                    $circuit_details->{'status'} = 'up';
                    $circuit_details->{'reason'} = $circuit_layout->{'reason'};
                    $circuit_details->{'type'} = 'change_path';
                    warn "Attempting to send notification\n";
		    $client->{'topic'} = 'OF.Notification.event';
                    $client->circuit_notification( $circuit_details );
		    $client->{'topic'} = 'OF.FWDCTL.RPC';
                }

            }else{
                #already done... nothing to do... complete the scheduled action
                syslog(LOG_WARNING,"Circuit " . $circuit_details->{'description'} . ":" . $circuit_details->{'circuit_id'} . " is already on Path:" . $circuit_layout->{'path'} . "completing scheduled action"); 
                my $res = $oess->update_action_complete_epoch( scheduled_action_id => $action->{'scheduled_action_id'});

                if(!defined($res)){
                    syslog(LOG_ERR,"Unable to complete action");
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


