#!/usr/bin/perl -T
#
##----- NDDI OESS provisioning.cgi
##-----
##----- Provides a WebAPI to allow for provisioning/decoming of circuits
##
##-------------------------------------------------------------------------
##
##
## Copyright 2011 Trustees of Indiana University
##
##   Licensed under the Apache License, Version 2.0 (the "License");
##   you may not use this file except in compliance with the License.
##   You may obtain a copy of the License at
##
##       http://www.apache.org/licenses/LICENSE-2.0
##
##   Unless required by applicable law or agreed to in writing, software
##   distributed under the License is distributed on an "AS IS" BASIS,
##   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
##   See the License for the specific language governing permissions and
##   limitations under the License.
#

use strict;
use warnings;

use CGI;
use JSON;
use Switch;
#use Net::DBus::Exporter qw(org.nddi.fwdctl);
use Data::Dumper;

use OESS::Database;
use OESS::Topology;
use OESS::Circuit;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

my $db = new OESS::Database();

my $cgi = new CGI;

$| = 1;

sub main {

    if ( !$db ) {
        send_json( { "error" => "Unable to connect to database." } );
        exit(1);
    }
    my $action = $cgi->param('action');
    warn Dumper $action;
    print STDERR "action " . $action;
    my $output;
    my $user = $db->get_user_by_id( user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];
    if ($user->{'status'} eq 'decom') {
        $action = "error";
    }
    switch ($action) {

        case "provision_circuit" {
	    $output = &provision_circuit();
	}
        case "remove_circuit" {
            $output = &remove_circuit();
        }
        case "fail_over_circuit" {
            $output = &fail_over_circuit();
        }
        case "reprovision_circuit"{
            $output = &reprovision_circuit();
        }
        case "error" {
            $output = { error => "Decommed users cannot use webservices."};
        } 
        else {
            $output = {
                       error => "Unknown action - $action"
                      };
        }

    }

    send_json($output);

}

sub _fail_over {
    my %args = @_;

    my $bus = Net::DBus->system;

    my $client;
    my $service;

    eval {
        $service = $bus->get_service("org.nddi.fwdctl");
        $client  = $service->get_object("/controller1");
    };

    if ($@) {
        warn "Error in _connect_to_fwdctl: $@";
    }
        
    if ( !defined($client) ) {
        return;
    }

    my $circuit_id = $args{'circuit_id'};

    my ($result,$event_id) = $client->changeVlanPath($circuit_id);

    warn "Failover RESULT: $result";

    my $final_res = FWDCTL_WAITING;

    while($final_res == FWDCTL_WAITING){
        sleep(1);
        $final_res = $client->get_event_status($event_id);
    }

    #warn "ADD RESULT: $result";

    return $final_res;

}

sub _send_add_command {
    my %args = @_;

    my $bus = Net::DBus->system;

    my $client;
    my $service;

    eval {
        $service = $bus->get_service("org.nddi.fwdctl");
        $client  = $service->get_object("/controller1");
    };

    if ($@) {
        warn "Error in _connect_to_fwdctl: $@";
        return undef;
    }

    if ( !defined $client ) {
        return undef;
    }

    my $circuit_id = $args{'circuit_id'};
    my ($result,$event_id) = $client->addVlan($circuit_id);

    my $final_res = FWDCTL_WAITING;

    while($final_res == FWDCTL_WAITING){
        sleep(1);
        $final_res = $client->get_event_status($event_id);
    }

    #warn "ADD RESULT: $result";

    return $final_res;
}

sub _send_remove_command {
    my %args = @_;

    my $bus = Net::DBus->system;

    my $client;
    my $service;

    eval {
        $service = $bus->get_service("org.nddi.fwdctl");
        $client  = $service->get_object("/controller1");
    };
    if ($@) {
        warn "Error in _connect_to_fwdctl: $@";
        return undef;
    }

    if ( !defined $client ) {
        return undef;
    }

    my $circuit_id = $args{'circuit_id'};

    my ($result,$event_id) = $client->deleteVlan($circuit_id);

    my $final_res = FWDCTL_WAITING;

    while($final_res == FWDCTL_WAITING){
        sleep(1);
        $final_res = $client->get_event_status($event_id);
    }

    #warn "ADD RESULT: $result";

    return $final_res;

}

sub _send_update_cache{
    my %args = @_;
    if(!defined($args{'circuit_id'})){
        $args{'circuit_id'} = -1;
    }
    my $bus = Net::DBus->system;

    my $client;
    my $service;

    eval {
        $service = $bus->get_service("org.nddi.fwdctl");
        $client  = $service->get_object("/controller1");
    };

    if ($@) {
        warn "Error in _connect_to_fwdctl: $@";
        return undef;
    }

    if ( !defined $client ) {
        return undef;
    }

    my ($result,$event_id) = $client->update_cache($args{'circuit_id'});

    my $final_res = FWDCTL_WAITING;

    while($final_res == FWDCTL_WAITING){
        sleep(1);
        $final_res = $client->get_event_status($event_id);
    }

    #warn "ADD RESULT: $result";

    return $final_res;
}

sub provision_circuit {
    my $results;

    $results->{'results'} = [];


    my $output;

    my $workgroup_id = $cgi->param('workgroup_id');
    my $external_id  = $cgi->param('external_identifier');

    my $circuit_id  = $cgi->param('circuit_id');
    my $description = $cgi->param('description');
    my $bandwidth   = $cgi->param('bandwidth');

    # TEMPORARY HACK UNTIL OPENFLOW PROPERLY SUPPORTS QUEUING. WE CANT
    # DO BANDWIDTH RESERVATIONS SO FOR NOW ASSUME EVERYTHING HAS 0 BANDWIDTH RESERVED
    $bandwidth = 0;

    my $provision_time = $cgi->param('provision_time');
    my $remove_time    = $cgi->param('remove_time');

    my $restore_to_primary = $cgi->param('restore_to_primary');
    my $static_mac = $cgi->param('static_mac');

    my $bus = Net::DBus->system;
    my $log_svc;
    my $log_client;
    eval {
        $log_svc    = $bus->get_service("org.nddi.notification");
        $log_client = $log_svc->get_object("/controller1");
    };
    warn $@ if $@;


    my @links         = $cgi->param('link');
    my @backup_links  = $cgi->param('backup_link');
    my @nodes         = $cgi->param('node');
    my @interfaces    = $cgi->param('interface');
    my @tags          = $cgi->param('tag');
    my @mac_addresses = $cgi->param('mac_address');
    my @endpoint_mac_address_nums = $cgi->param('endpoint_mac_address_num');
    my $loop_node   =$cgi->param('loop_node');
    #my $loop_name = $cgi->param('loop_name');
    my $state = $cgi->param('state') || 'active';

    my @remote_nodes = $cgi->param('remote_node');
    my @remote_tags  = $cgi->param('remote_tag');
    
    my $remote_url   = $cgi->param('remote_url');
    my $remote_requester = $cgi->param('remote_requester');
    
    my $workgroup = $db->get_workgroup_by_id( workgroup_id => $workgroup_id );

    if(!defined($workgroup)){
	return {error => 'unable to find workgroup $workgroup_id'};
    }elsif ( $workgroup->{'name'} eq 'Demo' ) {
        return { error => 'sorry this is a demo account, and can not actually provision' };
    }elsif($workgroup->{'status'} eq 'decom'){
	return {error => 'The selected workgroup is decomissioned and unable to provision'};
    }

    my $user = $db->get_user_by_id(user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];

    if($user->{'type'} eq 'read-only'){
        return {error => 'You are a read-only user and unable to provision'};
    }
    if ( !$circuit_id || $circuit_id == -1 ) {
        #Register with DB
        $output = $db->provision_circuit(
            description    => $description,
            remote_url => $remote_url,
            remote_requester => $remote_requester,
            bandwidth      => $bandwidth,
            provision_time => $provision_time,
            remove_time    => $remove_time,
            links          => \@links,
            backup_links   => \@backup_links,
            nodes          => \@nodes,
            interfaces     => \@interfaces,
            tags           => \@tags,
            mac_addresses  => \@mac_addresses,
            endpoint_mac_address_nums  => \@endpoint_mac_address_nums,
            user_name      => $ENV{'REMOTE_USER'},
            workgroup_id   => $workgroup_id,
            external_id    => $external_id,
            restore_to_primary => $restore_to_primary,
            static_mac => $static_mac,
            state => $state
            );

        if ( defined $output && $provision_time <= time() && ($state eq 'active')) {

            my $result = _send_add_command( circuit_id => $output->{'circuit_id'} );

            if ( !defined $result ) {
                $output->{'warning'} =
                  "Unable to talk to fwdctl service - is it running?";
            }

            # failure, remove the circuit now
            if ( $result == 0 ) {
                $cgi->param( 'circuit_id',  $output->{'circuit_id'} );
                $cgi->param( 'remove_time', -1 );
                $cgi->param( 'force',       1 );
                my $removal = remove_circuit();

                #warn "Removal status: " . Data::Dumper::Dumper($removal);
                $results->{'error'} =
                  "Unable to provision circuit. Please check your logs or contact your server adminstrator for more information. Circuit has been removed.";
                return $results;
            }

            #if we're here we've successfully provisioned onto the network, so log notification.
            if (defined $log_client) {
                eval{
                    my $circuit_details = $db->get_circuit_details( circuit_id => $output->{'circuit_id'} );
                    $circuit_details->{'status'} = 'up';
                    $circuit_details->{'reason'} = 'provisioned';
                    $circuit_details->{'type'} = 'provisioned';
                    $log_client->circuit_notification( $circuit_details  );
                };
                warn $@ if $@;
            }
        }

    } else {

        my %edit_circuit_args = (
            circuit_id     => $circuit_id,
            description    => $description,
            bandwidth      => $bandwidth,
            provision_time => $provision_time,
            restore_to_primary => $restore_to_primary,
            remove_time    => $remove_time,
            links          => \@links,
            backup_links   => \@backup_links,
            nodes          => \@nodes,
            interfaces     => \@interfaces,
            tags           => \@tags,
            mac_addresses  => \@mac_addresses,
            endpoint_mac_address_nums  => \@endpoint_mac_address_nums,
            user_name      => $ENV{'REMOTE_USER'},
            workgroup_id   => $workgroup_id,
            do_external    => 0,
            static_mac => $static_mac,
            do_sanity_check => 0,
            loop_node => $loop_node,
            state  => $state
        );

        ##Edit Existing Circuit
        # verify is allowed to modify circuit ISSUE=7690
        # and perform all other sanity checks on circuit 10278
        if(!$db->circuit_sanity_check(%edit_circuit_args)){
            return {'results' => [], 'error' => $db->get_error() };
        }
       
        # remove flows on switch 
        my $result = _send_remove_command( circuit_id => $circuit_id );
        if ( !$result ) {
            $output->{'warning'} =
              "Unable to talk to fwdctl service - is it running?";
              $results->{'error'} = "Unable to talk to fwdctl service - is it running?";

            return $results;
        }
        if ( $result == 0 ) {
            $results->{'error'} =
              "Unable to remove circuit. Please check your logs or contact your server adminstrator for more information. Circuit has been left in the database.";
            return $results;
        }
        # modify database entry
        $output = $db->edit_circuit(%edit_circuit_args);
        if (!$output) {
            return {
                'error'   =>  $db->get_error(),
                'results' => []
            };
        }
        # add flows on switch
        $result = _send_add_command( circuit_id => $output->{'circuit_id'} );
        if ( !defined $result ) {
            $output->{'warning'} =
              "Unable to talk to fwdctl service - is it running?";
        }
        if ( $result == 0 ) {
            $results->{'error'} =
              "Unable to edit circuit. Please check your logs or contact your server adminstrator for more information. Circuit is likely not live on the network anymore.";
            return $results;
        }

        #Send Edit to Syslogger DBUS
        if ( defined $log_client ) {
            eval{
                my $circuit_details = $db->get_circuit_details( circuit_id => $output->{'circuit_id'} );
                $circuit_details->{'status'} = 'up';
                $circuit_details->{'reason'} = 'edited';
                $circuit_details->{'type'} = 'modified';
                $log_client->circuit_notification( $circuit_details  );
            };
            warn $@ if $@;
        }
    }

    if ( !defined $output ) {
        $results->{'error'} = $db->get_error();
    } else {
        $results->{'results'} = $output;
    }

    return $results;
}

sub remove_circuit {
    my $results;

    my $circuit_id   = $cgi->param('circuit_id');
    my $remove_time  = $cgi->param('remove_time');
    my $workgroup_id = $cgi->param('workgroup_id');
    $results->{'results'} = [];

    my $can_remove = $db->can_modify_circuit(
                                             circuit_id   => $circuit_id,
                                             username     => $ENV{'REMOTE_USER'},
                                             workgroup_id => $workgroup_id
                                            );

    my $bus = Net::DBus->system;
    my $log_svc;
    my $log_client;

    eval {
        $log_svc    = $bus->get_service("org.nddi.notification");
        $log_client = $log_svc->get_object("/controller1");
    };
    warn $@ if $@;

    if ( !defined $can_remove ) {
        $results->{'error'} = $db->get_error();
        return $results;
    }

    if ( $can_remove < 1 ) {
        $results->{'error'} =
          "Users and workgroup do not have permission to remove this circuit";
        return $results;
    }

    # removing it now, otherwise we'll just schedule it for later
    if ( $remove_time && $remove_time <= time() ) {
        my $result = _send_remove_command( circuit_id => $circuit_id );

        if ( !defined $result ) {
            $results->{'error'} =
              "Unable to talk to fwdctl service - is it running?";
            return $results;
        }

        if ( $result == 0 ) {
            $results->{'error'} =
              "Unable to remove circuit. Please check your logs or contact your server adminstrator for more information. Circuit has been left in the database.";

            # if force is sent, it will clear it from the database regardless of whether fwdctl reported success or not
            if ( !$cgi->param('force') ) {
                return $results;
            }
        }



    }

    my $output = $db->remove_circuit(
                                     circuit_id   => $circuit_id,
                                     remove_time  => $remove_time,
                                     username     => $ENV{'REMOTE_USER'},
                                     workgroup_id => $workgroup_id
                                    );

    _send_update_cache( circuit_id => $circuit_id);

    #    print STDERR Dumper($output);

    if ( !defined $output ) {
        $results->{'error'} = $db->get_error();
        return $results;
    } elsif ($remove_time <= time() ) {
        #only send removal event if it happened now, not if it was scheduled to happen later.
        #DBUS Log removal event
        eval{
            my $circuit_details = $db->get_circuit_details( circuit_id => $output->{'circuit_id'} );
            warn ("sending circuit_decommission");
            warn Dumper ($circuit_details);
            $circuit_details->{'status'} = 'removed';
            $circuit_details->{'reason'} = 'removed by ' . $ENV{'REMOTE_USER'};
            $circuit_details->{'type'} = 'removed';
            $log_client->circuit_notification( $circuit_details );
        };
        warn $@ if $@;

    }

    $results->{'results'} = [ { success => 1 } ];

    return $results;
}

sub reprovision_circuit {

    #removes and then re-adds circuit for
    my $results;

    my $circuit_id = $cgi->param('circuit_id');
    my $workgroup_id = $cgi->param('workgroup_id');

    my $can_reprovision = $db->can_modify_circuit(
                                                  circuit_id => $circuit_id,
                                                  username => $ENV{'REMOTE_USER'},
                                                  workgroup_id => $workgroup_id
                                                 );
    if ( !defined $can_reprovision ) {
        $results->{'error'} = $db->get_error();
        return $results;
    }
    if ( $can_reprovision < 1 ) {
        $results->{'error'} =
          "Users and workgroup do not have permission to remove this circuit";
        return $results;
    }

    my $success= _send_remove_command(circuit_id => $circuit_id);
    if (!$success) {
        $results->{'error'} = "Error sending circuit removal request to controller, please try again or contact your Systems Administrator";
        return $results;
    }
    my $add_success = _send_add_command(circuit_id => $circuit_id);
    if (!$add_success) {
        $results->{'error'} = "Error sending circuit provision request to controller, please try again or contact your Systems Administrator";
        return $results;
    }
    $results->{'results'} = [ {success => 1 } ];

    return $results;
}

sub fail_over_circuit {
    my $results;

    my $circuit_id   = $cgi->param('circuit_id');
    my $workgroup_id = $cgi->param('workgroup_id');
    my $forced = $cgi->param('force') || undef;

    my $bus = Net::DBus->system;
    my $log_svc;
    my $log_client;
    eval {
        $log_svc    = $bus->get_service("org.nddi.notification");
        $log_client = $log_svc->get_object("/controller1");
    };
    warn $@ if $@;

    my $can_fail_over = $db->can_modify_circuit(
                                                circuit_id   => $circuit_id,
                                                username     => $ENV{'REMOTE_USER'},
                                                workgroup_id => $workgroup_id
                                               );

    if ( !defined $can_fail_over ) {
        $results->{'error'} = $db->get_error();
        return $results;
    }

    if ( $can_fail_over < 1 ) {
        $results->{'error'} =
          "Users and workgroup do not have permission to remove this circuit";
        return $results;
    }

    my $ckt = OESS::Circuit->new( circuit_id => $circuit_id, db => $db);
    my $has_backup_path = $ckt->has_backup_path();
    if ($has_backup_path) {

        my $current_path = $ckt->get_active_path();
        my $alternate_path = 'primary';
        if($current_path eq 'primary'){
            $alternate_path = 'backup';
        }
        my $is_up = $ckt->get_path_status( path => $alternate_path );

        if ( $is_up || $forced ) {

            $ckt->change_path();
            my $result =
              _fail_over( circuit_id => $circuit_id, workgroup_id => $workgroup_id );
            if ( !defined($result) ) {
                $results->{'error'} = "Unable to change the path";
                $results->{'results'} = [ { success => 0 } ];
            }

            if ( $result == 0 ) {
                $results->{'error'} = "Unable to change the path";
                $results->{'results'} = [ { success => 0 } ];
            }

            my $circuit_details = $db->get_circuit_details( circuit_id => $circuit_id );

            if ($is_up) {
                eval {
                    $circuit_details->{'status'} = 'up';
                    $circuit_details->{'reason'} = "user " . $ENV{'REMOTE_USER'} . " forced the circuit to change to the alternate path";
                    $circuit_details->{'type'} = 'change_path';
                    $log_client->circuit_notification( $circuit_details );

                };
                warn $@ if $@;
            } elsif ($forced) {
                eval {
                    $circuit_details->{'status'} = 'down';
                    $circuit_details->{'reason'} = "user " . $ENV{'REMOTE_USER'} . " forced the circuit to change to the alternate path which is down!";
                    $log_client->circuit_notification( $circuit_details  );
                };
                warn $@ if $@;
            }
            $results->{'results'} = [ { success => 1 } ];
        } else {

            $results->{'error'}{'message'} = "Alternative Path is down, failing over will cause this circuit to be down.";
            $results->{'results'} = [ {
                                       'success' =>0,
                                       alt_path_down => 1 } ];
        }
    }
    return $results;
}

sub send_json {
    my $output = shift;
    print "Content-type: text/plain\n\n" . encode_json($output);
}

main();
