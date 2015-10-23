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

sub main{
    openlog("oess_scheduler.pl", 'cons,pid', LOG_DAEMON);
    my $time = time();

    my $oess = OESS::Database->new();
    
    my $bus = Net::DBus->system;
    my $service;
    my $client;

    eval {
        $service = $bus->get_service("org.nddi.fwdctl");
        $client  = $service->get_object("/controller1");
    };

    if ($@){
        syslog(LOG_ERR,"Error in _connect_to_fwdctl: $@");
        return undef;
    }

    my $log_svc;
    my $log_client;

    eval {
        $log_svc    = $bus->get_service("org.nddi.notification");
        $log_client = $log_svc->get_object("/controller1");
    };


    my $actions = $oess->get_current_actions();

    foreach my $action (@$actions){
        
        my $circuit_layout = XMLin($action->{'circuit_layout'}, forcearray => 1);
        
        if($circuit_layout->{'action'} eq 'provision'){

            syslog(LOG_DEBUG,"Circuit " . $circuit_layout->{'name'} . ":" . $circuit_layout->{'circuit_id'} . " scheduled for activation NOW!");
            my $user = $oess->get_user_by_id( user_id => $action->{'user_id'} )->[0];
            my $ckt = $oess->get_circuit_by_id( circuit_id => $action->{'circuit_id'})->[0];
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
            my $event_id;
            eval {
                ($res,$event_id) = $client->addVlan($output->{'circuit_id'});
                
                my $final_res = OESS::Database->FWDCTL_WAITING;

                while($final_res == OESS::Database->FWDCTL_WAITING){
                    sleep(1);
                    $final_res = $client->get_event_status($event_id);
                }

                $res = $final_res;
            };
            
            
            $oess->update_action_complete_epoch( scheduled_action_id => $action->{'scheduled_action_id'});
            

            #--- signal fwdctl to update caches
            eval{
                my ($result,$event_id) = $client->update_cache($action->{'circuit_id'});

		my $update_cache_result = OESS::Database->FWDCTL_WAITING;

		while($update_cache_result == OESS::Database->FWDCTL_WAITING){
		    sleep(1);
                    $update_cache_result = $client->get_event_status($event_id);
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
                $log_client->circuit_notification( $circuit_details );
            };
            
            
        } elsif($circuit_layout->{'action'} eq 'edit'){
            syslog(LOG_DEBUG,"Circuit " . $circuit_layout->{'name'} . ":" . $circuit_layout->{'circuit_id'} . " scheduled for edit NOW!");
            my $res;
            my $event_id;
            eval {
                ($res,$event_id) = $client->deleteVlan($action->{'circuit_id'});
                my $final_res = OESS::Database->FWDCTL_WAITING;

                while($final_res == OESS::Database->FWDCTL_WAITING){
                    sleep(1);
                    $final_res = $client->get_event_status($event_id);
                }

                $res = $final_res;
            };
            
            my $ckt = $oess->get_circuit_by_id(circuit_id => $action->{'circuit_id'})->[0];
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
            $event_id = undef;;
            eval{
                if($circuit_layout->{'state'} eq 'active' ){

                    ($res,$event_id) = $client->addVlan($output->{'circuit_id'});
                    
                    my $final_res = OESS::Database->FWDCTL_WAITING;
                    
                    while($final_res == OESS::Database->FWDCTL_WAITING){
                        sleep(1);
                        $final_res = $client->get_event_status($event_id);
                    }
                    $res = $final_res;
                }
            };
            
            $oess->update_action_complete_epoch( scheduled_action_id => $action->{'scheduled_action_id'});
            
            #--- signal fwdctl to update caches
            eval{
                my ($result,$event_id) = $client->update_cache($action->{'circuit_id'});

		my $update_cache_result = OESS::Database->FWDCTL_WAITING;

		while($update_cache_result == OESS::Database->FWDCTL_WAITING){
		    sleep(1);
                    $update_cache_result = $client->get_event_status($event_id);
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
                $log_client->circuit_notification( $circuit_details );
            };

        }
        elsif($circuit_layout->{'action'} eq 'remove'){
            syslog(LOG_ERR, "Circuit " . $circuit_layout->{'name'} . ":" . $action->{'circuit_id'} . " scheduled for removal NOW!");
            my $res;
            my $event_id;
            eval{
                ($res,$event_id) = $client->deleteVlan($action->{'circuit_id'});

                my $final_res = OESS::Database->FWDCTL_WAITING;

                while($final_res == OESS::Database->FWDCTL_WAITING){
                    sleep(1);
                    $final_res = $client->get_event_status($event_id);
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
                my ($result,$event_id) = $client->update_cache($action->{'circuit_id'});

                my $update_cache_result = OESS::Database->FWDCTL_WAITING;
                
                while($update_cache_result == OESS::Database->FWDCTL_WAITING){
                    sleep(1);
                    $update_cache_result = $client->get_event_status($event_id);
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
                $log_client->circuit_notification($circuit_details);
            };

        }elsif($circuit_layout->{'action'} eq 'change_path'){
            syslog(LOG_ERR,"Found a change_path action!!\n");
            #verify the circuit has an alternate path
            my $circuit = OESS::Circuit->new( db=>$oess, circuit_id => $action->{'circuit_id'});
            my $circuit_details = $circuit->{'details'};
            
            #if we are already on our scheduled path... don't change
            if($circuit_details->{'active_path'} ne $circuit_layout->{'path'}){
                syslog(LOG_INFO,"Changing the patch of circuit " . $circuit_details->{'description'} . ":" . $circuit_details->{'circuit_id'});
                my $success = $circuit->change_path();
                #my $success = 1;
                my $res;
                my $event_id;
                if($success){
                    eval{
                        ($res,$event_id) = $client->changeVlanPath($action->{'circuit_id'});
                        my $final_res = OESS::Database->FWDCTL_WAITING;

                        while($final_res == OESS::Database->FWDCTL_WAITING){
                            sleep(1);
                            $final_res = $client->get_event_status($event_id);
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
                    $log_client->circuit_notification( $circuit_details );
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


