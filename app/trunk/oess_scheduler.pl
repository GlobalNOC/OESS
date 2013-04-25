#!/usr/bin/perl

use strict;
use OESS::Database;
use OESS::DBus;
use XML::Simple;
use Sys::Syslog qw(:standard :macros);
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
	syslog(LOG_ERROR,"Error in _connect_to_fwdctl: $@");
        return undef;
    }

	 my $log_svc;
     my $log_client;

    eval {
        $log_svc    = $bus->get_service("org.nddi.syslogger");
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
					     remove_time    => -1,
					     links          => $circuit_layout->{'links'},
					     backup_links   => $circuit_layout->{'backup_links'},
					     nodes          => $circuit_layout->{'nodes'},
					     interfaces     => $circuit_layout->{'interfaces'},
					     tags           => $circuit_layout->{'tags'},
					     status         => 'active',
					     user_name      => $user->{'auth_name'},
					     workgroup_id   => $action->{'workgroup_id'},
					     description    => $ckt->{'description'}
		);

	    my $res;
	    eval {
		$res = $client->addVlan($output->{'circuit_id'});
	    };
	    
	    $oess->update_action_complete_epoch( scheduled_action_id => $action->{'scheduled_action_id'});

	}elsif($circuit_layout->{'action'} eq 'edit'){
	    syslog(LOG_DEBUG,"Circuit " . $circuit_layout->{'name'} . ":" . $circuit_layout->{'circuit_id'} . " scheduled for edit NOW!");
	    my $res;
	    eval {
		$res = $client->deleteVlan($action->{'circuit_id'});
	    };

	    my $ckt = $oess->get_circuit_by_id(circuit_id => $action->{'circuit_id'})->[0];
	    my $user = $oess->get_user_by_id( user_id => $action->{'user_id'} )->[0];
	    my $output = $oess->edit_circuit(circuit_id => $action->{'circuit_id'},
					     name => $circuit_layout->{'name'},
					     bandwidth => $circuit_layout->{'bandwidth'},
					     provision_time => time(),
					     remove_time => -1,
					     links => $circuit_layout->{'links'},
					     backup_links => $circuit_layout->{'backup_links'},
					     nodes => $circuit_layout->{'nodes'},
					     interfaces => $circuit_layout->{'interfaces'},
					     tags => $circuit_layout->{'tags'},
					     status => 'active',
					     username => $user->{'auth_name'},
					     workgroup_id => $action->{'workgroup_id'},
					     description => $ckt->{'description'}
		);
	    
	    $res = undef;

	    eval{ 
		$res = $client->addVlan($output->{'circuit_id'});
	    };
	    $oess->update_action_complete_epoch( scheduled_action_id => $action->{'scheduled_action_id'});
	    
	}elsif($circuit_layout->{'action'} eq 'remove'){
	    syslog(LOG_ERR, "Circuit " . $circuit_layout->{'name'} . ":" . $action->{'circuit_id'} . " scheduled for removal NOW!");
	    my $res;
	    eval{
		$res = $client->deleteVlan($action->{'circuit_id'});
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
		
		
		#Delete is complete and successful, send event on DBUS Channel Syslogger listens on.
		
		my $circuit_details = $oess->get_circuit_details( circuit_id => $action->{'circuit_id'} );
		
		$log_client->circuit_decommission({
		    circuit_id    => $action->{'circuit_id'},
		    workgroup_id  => $action->{'workgroup_id'},
		    name          => $circuit_details->{'name'},
		    description   => $circuit_details->{'description'},
		    circuit_state => $circuit_details->{'circuit_state'}
						  });
	    }
	}
    }
}

main();


