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


use JSON;
use Switch;
#use Net::DBus::Exporter qw(org.nddi.fwdctl);
use Data::Dumper;

use GRNOC::RabbitMQ::Client;
use Time::HiRes qw(usleep);
use OESS::Database;
use OESS::Topology;
use OESS::Circuit;
use Time::HiRes qw(gettimeofday tv_interval);
use GRNOC::WebService;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

my $db = new OESS::Database();

#register web service dispatcher
my $svc = GRNOC::WebService::Dispatcher->new();

$| = 1;

sub main {
    
    if ( !$db ) {
        send_json( { "error" => "Unable to connect to database." } );
        exit(1);
    }

    if ( !$svc ){
	send_json( {"error" => "Unable to access GRNOC::WebService" });
	exit(1);
    }
    
    my $user = $db->get_user_by_id( user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];
    if ($user->{'status'} eq 'decom') {
        send_json("error");
	exit(1);
    }

    #register the WebService Methods
    register_webservice_methods();

    #handle the WebService request.
    $svc->handle_request();
        
}

sub register_webservice_methods {
    
    my $method;
    
    #provision circuit
    $method = GRNOC::WebService::Method->new(
	name            => "provision_circuit",
	description     => "Adds or modifies a circuit on the network",
	callback        => sub { provision_circuit( @_ ) }
	);

    #add the required input parameter workgroup_id
    $method->add_input_parameter(
	name            => 'workgroup_id',
	pattern         => $GRNOC::WebService::Regex::INTEGER,
	required        => 1,
	description     => "The workgroup_id with permission to build the circuit, the user must be a member of this workgroup."
	); 

    $method->add_input_parameter(
	name => 'type',
	pattern => $GRNOC::WebService::Regex::NAME_ID,
	required => 0,
	default => 'openflow',
	description => "type of circuit (openflow|mpls)"
	);
    
    #add the optional input parameter external_identifier
     $method->add_input_parameter(
	 name            => 'external_identifier',
	 pattern         => $GRNOC::WebService::Regex::TEXT,
	 required        => 0,
	 description     => "External Identifier of the circuit"
	 ); 


    #add the optional input parameter circuit_id
     $method->add_input_parameter(
	 name            => 'circuit_id',
	 pattern         => $GRNOC::WebService::Regex::INTEGER,
	 required        => 0,
	 description     => "---1 or undefined indicated circuit is to be added."
	 ); 
    
    #add the required input parameter description
     $method->add_input_parameter(
	 name            => 'description',
	 pattern         => $GRNOC::WebService::Regex::TEXT,
	 required        => 1,
	 description     => "The description of the circuit."
	 ); 

    #add the optional input parameter bandwidth
     $method->add_input_parameter(
	 name            => 'bandwidth',
	 pattern         => $GRNOC::WebService::Regex::INTEGER,
	 required        => 0,
	 description     => "The dedicated bandwidth of the circuit in Mbps."
	 ); 

    #add the required input parameter provision_time
    $method->add_input_parameter(
	name            => 'provision_time',
	pattern         => $GRNOC::WebService::Regex::TEXT,
	required        => 1,
	description     => "Timestamp of when circuit should be created in epoch time format. - 1 means now."
	); 

    #add the required input parameter remove_time
     $method->add_input_parameter(
	 name            => 'remove_time',
	 pattern         => $GRNOC::WebService::Regex::TEXT,
	 required        => 1,
	 description     => "The time the circuit should be removed from the network in epoch time format. ---1 means never."
	 ); 
    
    #add the optional input parameter restore_to_primary
    $method->add_input_parameter(
	name            => 'restore_to_primary',
	pattern         => $GRNOC::WebService::Regex::INTEGER,
	required        => 0,
	description     => "Time in minutes to restore to primary (setting to 0 disables restore to primary)."
	); 

    #add the optional input parameter static_mac
    $method->add_input_parameter(
	name            => 'static_mac',
	pattern         => $GRNOC::WebService::Regex::BOOLEAN,
	required        => 0,
	description     => "Specifies if a circuit to beprovisioned is static_mac or not. Default is ‘0’."
	); 

    #add the required input parameter link
    $method->add_input_parameter(
	name            => 'link',
	pattern         => $GRNOC::WebService::Regex::TEXT,
	required        => 0,
	multiple        => 1,
	description     => "Array of names of links to be used in the primary path."
	); 

    #add the required input parameter backup_link
    $method->add_input_parameter(
	name            => 'backup_link',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 0,
        multiple        => 1,
        description     => "Array of names of links to be used in the backup path."
	);

    #add the required input parameter node
    $method->add_input_parameter(
        name            => 'node',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        multiple        => 1,
        description     => "Array of nodes to be used."
	);

    #add the required input parameter interface
    $method->add_input_parameter(
        name            => 'interface',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        multiple        => 1,
        description     => "Array of interfaces to be used. Note that interface[0] is on node[0]."
	);

    #add the required input parameter tag
    $method->add_input_parameter(
        name            => 'tag',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        multiple        => 1,
        description     => "An array of vlan tags to be used on each interface. Note that tag[0] is on interface[0] and tag[1] is on interface[1]."
	);

    #add the optional paramter loop_node
    $method->add_input_parameter(
        name            => 'loop_node',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 0,
        description     => "The node to be included when the circuit is looped."
	);

    #add the optional input parameter mac_addressess
    $method->add_input_parameter(
        name            => 'mac_address',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 0,
        multiple        => 1,
        description     => "Array of mac address of endpoints for static mac circuits."
	);

    #add the optional input parameter endpoint_mac_address_num
    $method->add_input_parameter(
        name            => 'endpoint_mac_address_num',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 0,
        multiple        => 1,
        description     => "Array of mac address of endpoints for static mac circuits."
        );

    #add the optional input parameter state
    $method->add_input_parameter(
	name            => 'state',
	pattern         => $GRNOC::WebService::Regex::TEXT,
	required        => 0,
	description     => "The state of the circuit."
	); 

    #add the optional input parameter remote_node
    $method->add_input_parameter(
	name            => 'remote_node',
	pattern         => $GRNOC::WebService::Regex::TEXT,
	required        => 0,
	multiple        => 1,
	description     => "Array of OSCARS URNs to use as endpoints for IDC based circuits."
	); 

    #add the optional input parameter remote_tag
    $method->add_input_parameter(
        name            => 'remote_tag',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        =>  0,
	multiple        =>  1,
        description     => "VLAN tags to be used on the IDC endpoints."
	);

    #add the optional input parameter remote_url
    $method->add_input_parameter(
        name            => 'remote_url',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 0,
        description     => "The remote URL for the IDC"
	);

    #add the optiona input parameter remote_requester
    $method->add_input_parameter(
        name            => 'remote_requester',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 0,
        description     => "The remote requester."
	);

    #register the provision_circuit() method
    $svc->register_method($method);

    #remove_circuit()
    $method = GRNOC::WebService::Method->new(
	name            => "remove_circuit",
	description     => "Removes a circuit from the network, and returns success if the circuit has been removed successfully or scheduled for removal from the network.",
	callback        => sub { remove_circuit( @_ ) }
	);

    $method->add_input_parameter(
        name            => 'type',
        pattern         => $GRNOC::WebService::Regex::NAME_ID,
        required        => 0,
	default         => 'openflow',
        description     => "The id of the circuit to be removed."
        );

    #add the required input parameter circuit_id
    $method->add_input_parameter(
        name            => 'circuit_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The id of the circuit to be removed."
        );
    
    #add the required input parameter remove_time
    $method->add_input_parameter(
        name            => 'remove_time',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The time for the circuit to be removed in epoch time. ---1 means now."
        );
    #add the required input paramater workgroup_id
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The workgroup ID that the circuit belongs to."
        );
    
    #add the optional input parameter force
    $method->add_input_parameter(
        name            => 'force',
        pattern         => $GRNOC::WebService::Regex::BOOLEAN,
        required        => 0,
        description     => "Clear the database regardless of whether fwdctl reported success or not."
        );
    
    #register the remove_circuit() method
    $svc->register_method($method);

    #fail_over_circuit()
     $method = GRNOC::WebService::Method->new(
	 name            => "fail_over_circuit",
	 description     => "Changes a circuit over to its backup path (if it has one)",
	 callback        => sub {  fail_over_circuit( @_ ) }
	 );

    #register the required input parameter circuit_id
    $method->add_input_parameter(
        name            => 'circuit_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The id of the circuit to be failed over."
        );
    #register the required input parameter workgroup_id
    $method->add_input_parameter(
        name            => 'workgroup_id',
	pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
	description     => "The workgroup ID that the circuit belongs to."
	);

    #register the optional input parameter forced
    $method->add_input_parameter(
        name            => 'force',
        pattern         => $GRNOC::WebService::Regex::BOOLEAN,
        required        => 0,
        description     => "If the circuit has to be forcefully failed over even if alternate path is down."
        );

    #register the fail_over_circuit() method
    $svc->register_method($method);

    #reprovision_circuit 
    $method = GRNOC::WebService::Method->new(
	name            => "reprovision_circuit",
	description     => "Removes and reinstalls all flow rules related to a circuit on the network.",
	callback        => sub {  reprovision_circuit ( @_ ) }
	);

    #register the required input parameter circuit_id
    $method->add_input_parameter(
        name            => 'circuit_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The id of the circuit to be re-provisioned."
        );
    #register the required input parameter workgroup_id
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The workgroup ID that the circuit belongs to."
        );

    $method->add_input_parameter(
        name            => 'type',
        pattern         => $GRNOC::WebService::Regex::NAME_ID,
        required        => 0,
        default         => 'openflow',
        description     => "The id of the circuit to be removed."
        );

    #register the reprovision_circuit()  method
    $svc->register_method($method);
    
}

sub _fail_over {
    my %args = @_;

    my $client  = new GRNOC::RabbitMQ::Client(
        topic => 'MPLS.FWDCTL.RPC',
        exchange => 'OESS',
        user => 'guest',
        pass => 'guest',
        host => 'localhost',
        port => 5672
        );

    if ( !defined($client) ) {
        return;
    }

    my $circuit_id = $args{'circuit_id'};

    my $result = $client->changeVlanPath(circuit_id => $circuit_id);

    if($result->{'error'} || !($result->{'results'})){
        return;
    }

    my $event_id = $result->{'results'}->{'event_id'};

    my $final_res = FWDCTL_WAITING;

    while($final_res == FWDCTL_WAITING){
        usleep(1000);
        my $res = $client->get_event_status(event_id => $event_id);

        if($res->{'error'} || !defined($res->{'results'}) || !defined($res->{'results'}->{'status'})){
            return;
        }

        $final_res = $res->{'results'}->{'status'};
    }

    return $final_res;
}

sub _send_mpls_add_command {
    my %args = @_;

    my $client  = new GRNOC::RabbitMQ::Client(
        topic => 'MPLS.FWDCTL.RPC',
        exchange => 'OESS',
        user => 'guest',
        pass => 'guest',
        host => 'localhost',
        port => 5672
        );

    if ( !defined($client) ) {
        return;
    }

    my $circuit_id = $args{'circuit_id'};

    my $result = $client->addVlan(circuit_id => $circuit_id);

    if($result->{'error'} || !defined $result->{'results'}){
        return;
    }

    my $event_id = $result->{'results'}->{'event_id'};

    my $final_res = FWDCTL_WAITING;
    while($final_res == FWDCTL_WAITING){
        usleep(1000);
        my $res = $client->get_event_status(event_id => $event_id);

        if(defined($res->{'error'}) || !defined($res->{'results'})){
            return;
        }

        $final_res = $res->{'results'}->{'status'};
    }

    return $final_res;
}

sub _send_add_command {
    my %args = @_;

    my $client  = new GRNOC::RabbitMQ::Client(
        topic => 'OF.FWDCTL.RPC',
        exchange => 'OESS',
        user => 'guest',
        pass => 'guest',
        host => 'localhost',
        port => 5672
        );

    if ( !defined($client) ) {
        return;
    }

    my $circuit_id = $args{'circuit_id'};

    my $result = $client->addVlan(circuit_id => $circuit_id);

    if($result->{'error'} || !defined $result->{'results'}){
        return;
    }

    my $event_id = $result->{'results'}->{'event_id'};

    my $final_res = FWDCTL_WAITING;
    while($final_res == FWDCTL_WAITING){
        usleep(1000);
        my $res = $client->get_event_status(event_id => $event_id);

        if(defined($res->{'error'}) || !defined($res->{'results'})){
            return;
        }

        $final_res = $res->{'results'}->{'status'};
    }

    return $final_res;
}

sub _send_mpls_remove_command {
    my %args = @_;

    my $client  = new GRNOC::RabbitMQ::Client(
        topic => 'MPLS.FWDCTL.RPC',
        exchange => 'OESS',
        user => 'guest',
        pass => 'guest',
        host => 'localhost',
        port => 5672
        );

    if ( !defined($client) ) {
        return;
    }

    my $circuit_id = $args{'circuit_id'};

    my $result = $client->deleteVlan(circuit_id => $circuit_id);

    if($result->{'error'} || !($result->{'results'})){
        return;
    }

    my $event_id = $result->{'results'}->{'event_id'};

    my $final_res = FWDCTL_WAITING;

    while($final_res == FWDCTL_WAITING){
        usleep(1000);
        my $res = $client->get_event_status(event_id => $event_id);

        if(defined($res->{'error'}) || !defined($res->{'results'})){
            return;
        }

        $final_res = $res->{'results'}->{'status'};
    }

    return $final_res;
}

sub _send_remove_command {
    my %args = @_;

    my $client  = new GRNOC::RabbitMQ::Client(
        topic => 'OF.FWDCTL.RPC',
        exchange => 'OESS',
        user => 'guest',
        pass => 'guest',
        host => 'localhost',
        port => 5672
        );

    if ( !defined($client) ) {
        return;
    }

    my $circuit_id = $args{'circuit_id'};

    my $result = $client->deleteVlan(circuit_id => $circuit_id);

    if($result->{'error'} || !($result->{'results'})){
        return;
    }

    my $event_id = $result->{'results'}->{'event_id'};

    my $final_res = FWDCTL_WAITING;

    while($final_res == FWDCTL_WAITING){
        usleep(1000);
        my $res = $client->get_event_status(event_id => $event_id);

        if(defined($res->{'error'}) || !defined($res->{'results'})){
            return;
        }

        $final_res = $res->{'results'}->{'status'};
    }

    return $final_res;
}

sub _send_update_cache{
    my %args = @_;
    if(!defined($args{'circuit_id'})){
        $args{'circuit_id'} = -1;
    }

    my $client  = new GRNOC::RabbitMQ::Client(
        topic => 'OF.FWDCTL.RPC',
        exchange => 'OESS',
        user => 'guest',
        pass => 'guest',
        host => 'localhost',
        port => 5672
        );

    if ( !defined($client) ) {
        return;
    }

    my $result = $client->update_cache(circuit_id => $args{'circuit_id'});

    if($result->{'error'} || !($result->{'results'})){
        return;
    }

    my $event_id = $result->{'results'}->{'event_id'};

    my $final_res = FWDCTL_WAITING;

    while($final_res == FWDCTL_WAITING){
        usleep(1000);
        my $res = $client->get_event_status(event_id => $event_id);

        if($res->{'error'} || $res->{'results'}){
            return;
        }

        $final_res = $client->get_event_status(event_id => $event_id)->{'results'}->{'status'};
    }

    return $final_res;
}

sub provision_circuit {

    
    my ( $method, $args ) = @_ ;
    my $results;

    my $start = [gettimeofday];

    $results->{'results'} = [];
    my $output;

    my $workgroup_id = $args->{'workgroup_id'}{'value'};
    my $external_id  = $args->{'external_identifier'}{'value'} || undef;

    my $circuit_id  = $args->{'circuit_id'}{'value'} || undef;
    my $description = $args->{'description'}{'value'};

    my $type = $args->{'type'}{'value'} || "openflow";

    # TEMPORARY HACK UNTIL OPENFLOW PROPERLY SUPPORTS QUEUING. WE CANT
    # DO BANDWIDTH RESERVATIONS SO FOR NOW ASSUME EVERYTHING HAS 0 BANDWIDTH RESERVED
    my $bandwidth   = $args->{'bandwidth'} || 0;

    my $provision_time = $args->{'provision_time'}{'value'};
    my $remove_time    = $args->{'remove_time'}{'value'};

    my $restore_to_primary = $args->{'restore_to_primary'}{'value'} || 0;
    my $static_mac = $args->{'static_mac'}{'value'} || 0;

    my @links         = $args->{'link'}{'value'};
    my @backup_links  = $args->{'backup_link'}{'value'};
    my @nodes         = $args->{'node'}{'value'};
    my @interfaces    = $args->{'interface'}{'value'};
    my @tags          = $args->{'tag'}{'value'};
    my @mac_addresses = $args->{'mac_address'}{'value'};
    my @endpoint_mac_address_nums = $args->{'endpoint_mac_address_num'}{'value'};
    my $loop_node     = $args->{'loop_node'}{'value'};
    my $state         = $args->{'state'}{'value'} || 'active';
    my @remote_nodes  = $args->{'remote_node'}{'value'};
    my @remote_tags   = $args->{'remote_tag'}{'value'};
    my $remote_url    = $args->{'remote_url'}{'value'};
    my $remote_requester = $args->{'remote_requester'}{'value'};
    
    my $rabbit_mq_start = [gettimeofday];

    my $log_client  = new GRNOC::RabbitMQ::Client(
        topic => 'OF.Notification.event',
        exchange => 'OESS',
        user => 'guest',
        pass => 'guest'
        );

    my $after_rabbit_mq = [gettimeofday];

    warn "Time to create rabbitMQ: " . tv_interval( $rabbit_mq_start, $after_rabbit_mq);

    if ( !defined($log_client) ) {
        return;
    }

    my $workgroup = $db->get_workgroup_by_id( workgroup_id => $workgroup_id );

    if(!defined($workgroup)){
	$method->set_error("unable to find workgroup $workgroup_id");
	return;
    }elsif ( $workgroup->{'name'} eq 'Demo' ) {
        $method->set_error('sorry this is a demo account, and can not actually provision');
	return;
    }elsif($workgroup->{'status'} eq 'decom'){
	$method->set_error('The selected workgroup is decomissioned and unable to provision');
	return;
    }

    my $user = $db->get_user_by_id(user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];

    if($user->{'type'} eq 'read-only'){
        $method->set_error('You are a read-only user and unable to provision');
        return;
    }
    if ( !$circuit_id || $circuit_id == -1 ) {
        #Register with DB

	my $before_provision = [gettimeofday];

        $output = $db->provision_circuit(
            description    => $description,
            remote_url => $remote_url,
            remote_requester => $remote_requester,
            bandwidth      => $bandwidth,
            provision_time => $provision_time,
            remove_time    => $remove_time,
            links          => @links,
            backup_links   => @backup_links,
            nodes          => @nodes,
            interfaces     => @interfaces,
            tags           => @tags,
            mac_addresses  => @mac_addresses,
            endpoint_mac_address_nums  => @endpoint_mac_address_nums,
            user_name      => $ENV{'REMOTE_USER'},
            workgroup_id   => $workgroup_id,
            external_id    => $external_id,
            restore_to_primary => $restore_to_primary,
            static_mac => $static_mac,
            state => $state,
	    type => $type
            );

	my $after_provision = [gettimeofday];

	warn "Time in DB: " . tv_interval( $before_provision, $after_provision);

        if(defined($output) && ($provision_time <= time()) && ($state eq 'active' || $state eq 'scheduled' || $state eq 'provisioned')) {

	    if($type eq 'openflow'){
		
		my $before_add_command = [gettimeofday];
		
		
		my $result = _send_add_command( circuit_id => $output->{'circuit_id'} );
		
		my $after_add_command = [gettimeofday];

		warn "Time waiting for add: " . tv_interval( $before_add_command, $after_add_command);

		if ( !defined $result ) {
		    $output->{'warning'} =
			"Unable to talk to fwdctl service - is it running?";
		}
		
		# failure, remove the circuit now
		if ( $result == 0 ) {
		    my $removal = remove_circuit(undef, {circuit_id => {value => $output->{'circuit_id'}},
							 remove_time => {value => -1},
							 force => {value => 1},
							 workgroup_id => {value => $workgroup_id},
							 type => {value => $type}}			);
		    
		    #warn "Removal status: " . Data::Dumper::Dumper($removal);
		    $method->set_error("Unable to provision circuit. Please check your logs or contact your server adminstrator for more information. Circuit has been removed.");
		    return;
		}
	    }

	    if($type eq 'mpls'){
		my $before_add_command = [gettimeofday];


                my $result = _send_mpls_add_command( circuit_id => $output->{'circuit_id'} );

                my $after_add_command = [gettimeofday];

                warn "Time waiting for add: " . tv_interval( $before_add_command, $after_add_command);

                if ( !defined $result ) {
                    $output->{'warning'} =
                        "Unable to talk to fwdctl service - is it running?";
                }

                # failure, remove the circuit now
                if ( $result == 0 ) {
                    my $removal = remove_circuit( {circuit_id => {value => $output->{'circuit_id'}},
						   remove_time => {value => -1},
						   force => {value => 1},
						   workgroup_id => {value => $workgroup_id},
						   type => {value => $type}});

                    #warn "Removal status: " . Data::Dumper::Dumper($removal);
                    $method->set_error("Unable to provision circuit. Please check your logs or contact your server adminstrator for more information. Circuit has been removed.");
                    return;
                }
            }

            #if we're here we've successfully provisioned onto the network, so log notification.
            if (defined $log_client) {
                eval{
                    my $circuit_details = $db->get_circuit_details( circuit_id => $output->{'circuit_id'} );
                    $circuit_details->{'status'} = 'up';
                    $circuit_details->{'reason'} = 'provisioned';
                    $circuit_details->{'type'} = 'provisioned';
                    $log_client->circuit_notification( circuit => $circuit_details,
						       no_reply => 1);
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
            links          => @links,
            backup_links   => @backup_links,
            nodes          => @nodes,
            interfaces     => @interfaces,
            tags           => @tags,
            mac_addresses  => @mac_addresses,
            endpoint_mac_address_nums  => @endpoint_mac_address_nums,
            user_name      => $ENV{'REMOTE_USER'},
            workgroup_id   => $workgroup_id,
            do_external    => 0,
            static_mac => $static_mac,
            do_sanity_check => 0,
            loop_node => $loop_node,
            state  => $state,
	    type   => $type
        );

        ##Edit Existing Circuit
        # verify is allowed to modify circuit ISSUE=7690
        # and perform all other sanity checks on circuit 10278
        if(!$db->circuit_sanity_check(%edit_circuit_args)){
            return {'results' => [], 'error' => $db->get_error() };
        }
       
        # remove flows on switch 
	if($type eq 'openflow'){
	    my $result = _send_remove_command( circuit_id => $circuit_id );
	    
	    if ( !$result ) {
		$output->{'warning'} =
		    "Unable to talk to fwdctl service - is it running?";
		$method->set_error("Unable to talk to fwdctl service - is it running?");
		
		return;
	    }
	    if ( $result == 0 ) {
		$method->set_error("Unable to remove circuit. Please check your logs or contact your server adminstrator for more information. Circuit has been left in the database.");
		return;
	    }
	    # modify database entry
	    $output = $db->edit_circuit(%edit_circuit_args);
	    if (!$output) {
		$method->set_error( db->get_error() );
		return;
	    }
	    # add flows on switch
	    if($state eq 'active' || $state eq 'looped'){
		$result = _send_add_command( circuit_id => $output->{'circuit_id'} );
		if ( !defined $result ) {
		    $output->{'warning'} =
			"Unable to talk to fwdctl service - is it running?";
		}
		if ( $result == 0 ) {
		    $method->set_error("Unable to edit circuit. Please check your logs or contact your server adminstrator for more information. Circuit is likely not live on the network anymore.");
		    return;
		}
	    }
	}else{
	    my $result = _send_mpls_remove_command( circuit_id => $circuit_id );

            if ( !$result ) {
                $output->{'warning'} =
                    "Unable to talk to fwdctl service - is it running?";
                $method->set_error("Unable to talk to fwdctl service - is it running?");

                return;
            }
            if ( $result == 0 ) {
                $method->set_error("Unable to remove circuit. Please check your logs or contact your server adminstrator for more information. Circuit has been left in the database.");
                return;
            }
            # modify database entry
            $output = $db->edit_circuit(%edit_circuit_args);
            if (!$output) {
                $method->set_error( db->get_error() );
                return;
            }
            # add flows on switch
            if($state eq 'active' || $state eq 'looped'){
                $result = _send_mpls_add_command( circuit_id => $output->{'circuit_id'} );
                if ( !defined $result ) {
                    $output->{'warning'} =
                        "Unable to talk to fwdctl service - is it running?";
                }
                if ( $result == 0 ) {
                    $method->set_error("Unable to edit circuit. Please check your logs or contact your server adminstrator for more information. Circuit is likely not live on the network anymore.");
                    return;
                }
            }
	}

        #Send Edit to Syslogger DBUS
        if ( defined $log_client ) {
            eval{
                my $circuit_details = $db->get_circuit_details( circuit_id => $output->{'circuit_id'} );
                $circuit_details->{'status'} = 'up';
                $circuit_details->{'reason'} = 'edited';
                $circuit_details->{'type'} = 'modified';
                $log_client->circuit_notification( circuit => $circuit_details,
						   no_reply => 1);
            };
            warn $@ if $@;
        }
    }

    if ( !defined $output ) {
        $method->set_error( $db->get_error() );
	return;
    } else {
        $results->{'results'} = $output;
    }

    return $results;
}

sub remove_circuit {
    my ( $method, $args ) = @_ ;
    my $results;

    my $circuit_id   = $args->{'circuit_id'}{'value'};
    my $remove_time  = $args->{'remove_time'}{'value'};
    my $workgroup_id = $args->{'workgroup_id'}{'value'};
    my $type         = $args->{'type'}{'value'} || "openflow";
    $results->{'results'} = [];

    my $can_remove = $db->can_modify_circuit(
	circuit_id   => $circuit_id,
	username     => $ENV{'REMOTE_USER'},
	workgroup_id => $workgroup_id
    );


    my $log_client  = new GRNOC::RabbitMQ::Client(
        topic => 'OF.Notification.event',
        exchange => 'OESS',
        user => 'guest',
        pass => 'guest'
        );

    if ( !defined($log_client) ) {
        $method->set_error("Internal server error occurred. Message queue connection failed.");
        return;
    }

    if ( !defined $can_remove ) {
        $method->set_error( $db->get_error() );
	return;
    }

    if ( $can_remove < 1 ) {
	$method->set_error('Users and workgroup do not have permission to remove this circuit');
	return;
    }

    # removing it now, otherwise we'll just schedule it for later
    if ( $remove_time && $remove_time <= time() ) {
	my $result;
	if($type eq 'openflow'){
	    $result = _send_remove_command( circuit_id => $circuit_id );
	}else{
	    $result = _send_mpls_remove_command( circuit_id => $circuit_id );
	}
        if ( !defined $result ) {
            $method->set_error("Unable to talk to fwdctl service - is it running?");
            return;
        }

        if ( $result == 0 ) {
            $method->set_error("Unable to remove circuit. Please check your logs or contact your server adminstrator for more information. Circuit has been left in the database");

            # If force is sent, it will clear it from the database
            # regardless of whether fwdctl reported success or not.
            # Otherwise the error is returned.
            if ( !$args->{'force'}{'value'} ) {
                return;
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
        $method->set_error( $db->get_error() );
	return;
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
            $log_client->circuit_notification( circuit => $circuit_details, 
                                               no_reply => 1,);
        };
        warn $@ if $@;

    }

    $results->{'results'} = [ { success => 1 } ];

    return $results;
}

sub reprovision_circuit {

    my ( $method, $args ) = @_ ;
    #removes and then re-adds circuit for
    my $results;

    my $circuit_id = $args->{'circuit_id'}{'value'};
    my $workgroup_id = $args->{'workgroup_id'}{'value'};

    my $circuit = OESS::Circuit->new( circuit_id => $circuit_id,
				      db => $db);

    my $can_reprovision = $db->can_modify_circuit(
	circuit_id => $circuit_id,
	username => $ENV{'REMOTE_USER'},
	workgroup_id => $workgroup_id
	);
    if ( !defined $can_reprovision ) {
        $method->set_error( $db->get_error() );
	return;
    }
    if ( $can_reprovision < 1 ) {
        $method->set_error("Users and workgroup do not have permission to remove this circuit");
	return;
    }

    if($circuit->get_type() eq 'openflow'){

	my $success= _send_remove_command(circuit_id => $circuit_id);
	if (!$success) {
	    $method->set_error('Error sending circuit removal request to controller, please try again or contact your Systems Administrator');
	return;
	}
	my $add_success = _send_add_command(circuit_id => $circuit_id);
	if (!$add_success) {
	    $method->set_error('Error sending circuit provision request to controller, please try again or contact your Systems Administrator');
	    return;
	    
	}
    }else{
        my $success= _send_mpls_remove_command(circuit_id => $circuit_id);
        if (!$success) {
            $method->set_error('Error sending circuit removal request to controller, please try again or contact your Systems Administrator');
        }
        my $add_success = _send_mpls_add_command(circuit_id => $circuit_id);
        if (!$add_success) {
            $method->set_error('Error sending circuit provision request to controller, please try again or contact your Systems Administrator');
            return;
        }
	
    }
    $results->{'results'} = [ {success => 1 } ];

    return $results;
}

sub fail_over_circuit {
    
    my ( $method, $args ) = @_ ;
    my $results;

    my $circuit_id   = $args->{'circuit_id'}{'value'};
    my $workgroup_id = $args->{'workgroup_id'}{'value'};
    my $forced = $args->{'force'}{'value'} || undef;

    my $log_client  = new GRNOC::RabbitMQ::Client(
        topic => 'OF.Notification.event',
        exchange => 'OESS',
        user => 'guest',
        pass => 'guest'
        );

    if ( !defined($log_client) ) {
        return;
    }

    my $can_fail_over = $db->can_modify_circuit(
	circuit_id   => $circuit_id,
	username     => $ENV{'REMOTE_USER'},
	workgroup_id => $workgroup_id
	);
    
    if ( !defined $can_fail_over ) {
        $method->set_error( $db->get_error() );
	return;
    }

    if ( $can_fail_over < 1 ) {
	$method->set_error( "Users and workgroup do not have permission to remove this circuit" );
	return;
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

            my $user_id = $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'});

            $ckt->change_path( user_id => $user_id, reason => "CHANGE PATH: User requested");
            my $result =
              _fail_over( circuit_id => $circuit_id, workgroup_id => $workgroup_id );
            if ( !defined($result) ) {
                $method->set_error('Unable to change the path');
		return;
            }

            if ( $result == 0 ) {
                $method->set_error('Unable to change the path');
                return;
            }

            my $circuit_details = $db->get_circuit_details( circuit_id => $circuit_id );

            if ($is_up) {
                eval {
                    $circuit_details->{'status'} = 'up';
                    $circuit_details->{'reason'} = "user " . $ENV{'REMOTE_USER'} . " forced the circuit to change to the alternate path";
                    $circuit_details->{'type'} = 'change_path';
                    $log_client->circuit_notification( circuit => $circuit_details,
			no_reply => 1);

                };
                warn $@ if $@;
            } elsif ($forced) {
                eval {
                    $circuit_details->{'status'} = 'down';
                    $circuit_details->{'reason'} = "user " . $ENV{'REMOTE_USER'} . " forced the circuit to change to the alternate path which is down!";
                    $log_client->circuit_notification( circuit => $circuit_details,
						       no_reply => 1);
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
    if (!defined($output) || !$output) {
        $output =  { "error" => "Server error in accessing webservices." };
    }
    print "Content-type: text/plain\n\n" . encode_json($output);
}

main();
