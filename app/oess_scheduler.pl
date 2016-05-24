#!/usr/bin/perl

use strict;
use OESS::Database;
use OESS::DBus;
use OESS::Circuit;
use XML::Simple;
use Sys::Syslog qw(:standard :macros);
use FindBin;
use Fcntl qw(:flock);
use Data::Dumper;

use GRNOC::RabbitMQ::Client;

sub main{
    openlog("oess_scheduler.pl", 'cons,pid', LOG_DAEMON);
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
        return;
    }

    my $actions = $oess->get_current_actions();

    foreach my $action (@$actions){
        my $ckt = $oess->get_circuit_by_id( circuit_id => $action->{'circuit_id'})->[0];
        my $circuit_layout = XMLin($action->{'circuit_layout'}, forcearray => 1);

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

            syslog(LOG_DEBUG,"Circuit " . $circuit_layout->{'name'} . ":" . $circuit_layout->{'circuit_id'} . " scheduled for activation NOW!");
            my $user = $oess->get_user_by_id( user_id => $action->{'user_id'} )->[0];

            #edit the circuit to make it active
            my $output = $oess->edit_circuit(circuit_id     => $action->{'circuit_id'},
                                             name           => $circuit_layout->{'name'},
                                             bandwidth      => $circuit_layout->{'bandwidth'},
                                             provision_time => time(),
                                             remove_time    => $circuit_layout->{'remove_time'},
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

            my $res;
            my $result;
            my $event_id;
            eval {
                $result = $client->addVlan(circuit_id => $output->{'circuit_id'});
                
                if($result->{'error'} || !$result->{'results'}->{'event_id'}){
                    return;
                }

                $event_id = $result->{'results'}->{'event_id'};

                my $final_res = OESS::Database->FWDCTL_WAITING;

                while($final_res == OESS::Database->FWDCTL_WAITING){
                    sleep(1);
                    $final_res = $client->get_event_status(event_id => $event_id)->{'event_id'}->{'status'};
                }

                $res = $final_res;
            };
            
            
            $oess->update_action_complete_epoch( scheduled_action_id => $action->{'scheduled_action_id'});
            

            #--- signal fwdctl to update caches
            eval{
                $result = $client->update_cache($action->{'circuit_id'});
                
                if($result->{'error'} || !$result->{'results'}->{'event_id'}){
                    return;
                }

                $event_id = $result->{'results'}->{'event_id'};

                my $update_cache_result = OESS::Database->FWDCTL_WAITING;
                
                while($update_cache_result == OESS::Database->FWDCTL_WAITING){
                    sleep(1);
                    $update_cache_result = $client->get_event_status(event_id => $event_id)->{'results'}->{'status'};
                }
                
                $res = $update_cache_result;
            };

            if(!defined $res || $res != OESS::Database->FWDCTL_SUCCESS){
                syslog(LOG_ERR,"Error updating cache after scheduled vlan removal.");
            }

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
            syslog(LOG_DEBUG,"Circuit " . $circuit_layout->{'name'} . ":" . $circuit_layout->{'circuit_id'} . " scheduled for edit NOW!");
            my $res;
            my $result;
            my $event_id;
            eval {
                $result = $client->deleteVlan(circuit_id => $action->{'circuit_id'});
                if($result->{'error'} || !$result->{'results'}->{'event_id'}){
                    return;
                }

                $event_id = $result->{'results'}->{'event_id'};
                my $final_res = OESS::Database->FWDCTL_WAITING;

                while($final_res == OESS::Database->FWDCTL_WAITING){
                    sleep(1);
                    $final_res = $client->get_event_status(event_id => $event_id)->{'results'}->{'status'};
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

            my $output = $oess->edit_circuit(circuit_id => $action->{'circuit_id'},
                                             name => $circuit_layout->{'name'},
                                             bandwidth => $circuit_layout->{'bandwidth'},
                                             provision_time => time(),
                                             remove_time => $circuit_layout->{'remove_time'},
                                             links => $circuit_layout->{'links'},
                                             backup_links => $circuit_layout->{'backup_links'},
                                             nodes => $circuit_layout->{'nodes'},
                                             interfaces => $circuit_layout->{'interfaces'},
                                             tags => $circuit_layout->{'tags'},
                                             state => $circuit_layout->{'state'},
                                             username => $user->{'auth_name'},
                                             workgroup_id => $action->{'workgroup_id'},
                                             description => $ckt->{'description'}
                );
            
            $res = undef;
            $result = undef;
            $event_id = undef;;
            eval{
                if($circuit_layout->{'state'} eq 'active'){

                    $result = $client->addVlan(circuit_id => $output->{'circuit_id'});
                    
                    if($result->{'error'} || !$result->{'results'}->{'event_id'}){
                        return;
                    }
                    
                    $event_id = $result->{'results'}->{'event_id'};

                    my $final_res = OESS::Database->FWDCTL_WAITING;
                    
                    while($final_res == OESS::Database->FWDCTL_WAITING){
                        sleep(1);
                        $final_res = $client->get_event_status(event_id => $event_id)->{'results'}->{'status'};
                    }
                    $res = $final_res;
                }
            };
            
            $oess->update_action_complete_epoch( scheduled_action_id => $action->{'scheduled_action_id'});
            
            #--- signal fwdctl to update caches
            eval{
                $result = $client->update_cache($action->{'circuit_id'});
                
                if($result->{'error'} || !$result->{'results'}->{'event_id'}){
                    return;
                }
                
                $event_id = $result->{'results'}->{'event_id'};

                my $update_cache_result = OESS::Database->FWDCTL_WAITING;
                
                while($update_cache_result == OESS::Database->FWDCTL_WAITING){
                    sleep(1);
                    $update_cache_result = $client->get_event_status(event_id => $event_id)->{'results'}->{'status'};
                }
                
                $res = $update_cache_result;
            };

            if(!defined $res || $res != OESS::Database->FWDCTL_SUCCESS){
                syslog(LOG_ERR,"Error updating cache after scheduled vlan removal.");
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
                $result = $client->deleteVlan(circuit_id => $action->{'circuit_id'});

                if($result->{'error'} || !$result->{'results'}->{'event_id'}){
                    return;
                }
                
                $event_id = $result->{'results'}->{'event_id'};

                my $final_res = OESS::Database->FWDCTL_WAITING;

                while($final_res == OESS::Database->FWDCTL_WAITING){
                    sleep(1);
                    $final_res = $client->get_event_status(event_id => $event_id)->{'results'}->{'status'};
                }

                $res = $final_res;
            };
            
            if(!defined($res)){
                syslog(LOG_ERR,"Res was not defined");
            }
            
            syslog(LOG_DEBUG,"Res: '" . $res . "'");
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
                my $result = $client->update_cache($action->{'circuit_id'});

                if($result->{'error'} || !$result->{'results'}->{'event_id'}){
                    return;
                }
                
                $event_id = $result->{'results'}->{'event_id'};

                my $update_cache_result = OESS::Database->FWDCTL_WAITING;
                
                while($update_cache_result == OESS::Database->FWDCTL_WAITING){
                    sleep(1);
                    $update_cache_result = $client->get_event_status(event_id => $event_id)->{'results'}->{'status'};
                }

                $res = $update_cache_result;
            };
            
            if(!defined $res || $res != OESS::Database->FWDCTL_SUCCESS){
                syslog(LOG_ERR,"Error updating cache after scheduled vlan removal.");
            }

            #Delete is complete and successful, send event on DBUS Channel Notification listens on.
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
                        $result = $client->changeVlanPath(circuit_id => $action->{'circuit_id'});

                        if($result->{'error'} || !$result->{'results'}->{'event_id'}){
                            return;
                        }
                        
                        $event_id = $result->{'results'}->{'event_id'};
                        my $final_res = OESS::Database->FWDCTL_WAITING;

                        while($final_res == OESS::Database->FWDCTL_WAITING){
                            sleep(1);
                            $final_res = $client->get_event_status(event_id => $event_id)->{'results'}->{'status'};
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


