#!/usr/bin/perl



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
use Data::Dumper;
use Log::Log4perl;

use GRNOC::Config;
use OESS::RabbitMQ::Client;
use Time::HiRes qw(usleep);
use OESS::Database;
use OESS::Topology;
use OESS::Circuit;
use OESS::VRF;
use Time::HiRes qw(gettimeofday tv_interval);
use GRNOC::WebService;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

Log::Log4perl::init('/etc/oess/logging.conf');

my $conf = GRNOC::Config->new(config_file => '/etc/oess/database.xml');

my $db = new OESS::Database();

my $mq = OESS::RabbitMQ::Client->new( topic    => 'OF.FWDCTL.RPC',
                                      timeout  => 120 );

my $svc = GRNOC::WebService::Dispatcher->new(method_selector => ['method', 'action']);

$| = 1;

sub main {
    
     if ( !$db ) {
         send_json( { "error" => "Unable to connect to database." } );
         exit(1);
     }

     if (!defined $mq ) {
         send_json( { "error" => "Unable to connect to RabbitMQ." } );
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
	callback        => sub { provision_circuit(@_) }
	);

    #add the required input parameter workgroup_id
    $method->add_input_parameter(
	name            => 'workgroup_id',
	pattern         => $GRNOC::WebService::Regex::INTEGER,
	required        => 1,
	description     => "The workgroup_id with permission to build the circuit, the user must be a member of this workgroup."
	); 
#this is autodetermined based on interfaces
#    $method->add_input_parameter(
#	name => 'type',
#	pattern => $GRNOC::WebService::Regex::NAME_ID,
#	required => 0,
#	default => 'openflow',
#	description => "type of circuit (openflow|mpls)"
#	);
    
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
        description     => 'Array of interfaces to be used. Note that interface[0] is on node[0].'
	);

    #add the required input parameter tag
    $method->add_input_parameter(
        name            => 'tag',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        multiple        => 1,
        description     => 'An array of vlan tags to be used on each interface. Note that tag[0] is on interface[0] and tag[1] is on interface[1].'
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


    #provision_vrf
    $method = GRNOC::WebService::Method->new(
	name            => "provision_vrf",
	description     => "Provisions a VRF (L3VPN) on the network",
	callback        => sub {  provision_vrf ( @_ ) }
    );
    
    $method->add_input_parameter(
	name            => 'vrf_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "If editing an existing VRF specify the ID otherwise leave blank for new VRF."
        );
    
    $method->add_input_parameter(
        name            => 'name',
        pattern         => $GRNOC::WebService::Regex::NAME_ID,
        required        => 1,
        description     => "The workgroup_id with permission to build the vrf, the user must be a member of this workgroup."
        );

    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The workgroup_id with permission to build the vrf, the user must be a member of this workgroup."
        );
    
    #add the required input parameter description
    $method->add_input_parameter(
        name            => 'description',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "The description of the circuit."
        );
    
    
    $method->add_input_parameter(
        name            => 'endpoint',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
	multiple        => 1,
        description     => "The JSON blob describing all of the endpoints"
        );
    
    $method->add_input_parameter(
        name            => 'local_asn',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The JSON blob describing all of the endpoints"
        );
    
    $method->add_input_parameter(
        name            => 'prefix_limit',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        default         => 1000,
        description     => "Maximum prefix limit size for BGP peer routes"
        );
    
    $method->add_input_parameter(
        name            => 'provision_time',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        default         => -1,
        description     => "time to provision -1 = now and unix timestamp for any other time"
        );

    $method->add_input_parameter(
        name            => 'remove_time',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        default         => -1,
        description     => "defaults to -1 for never otherwise takes a unix timestamp",
        );

    $svc->register_method($method);

    #remove_vrf
    $method = GRNOC::WebService::Method->new(
        name            => "remove_vrf",
        description     => "removes a VRF (L3VPN) from the network",
        callback        => sub {  remove_vrf ( @_ ) }
        );

    $method->add_input_parameter(
        name            => 'vrf_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "If editing an existing VRF specify the ID otherwise leave blank for new VRF."
        );

    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "If editing an existing VRF specify the ID otherwise leave blank for new VRF."
        );

    $method->add_input_parameter(
        name            => 'remove_time',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        default         => -1,
        description     => "defaults to -1 for now otherwise takes a unix timestamp",
        );

    $svc->register_method($method);


    
 }

sub _fail_over {
    my %args = @_;

    if (!defined $mq) {
	return;
    } else {
	$mq->{'topic'} = 'OF.FWDCTL.RPC';
    }

    my $circuit_id = $args{'circuit_id'};

    my $cv = AnyEvent->condvar;

    $mq->changeVlanPath(circuit_id => $circuit_id,
			async_callback => sub {
			    my $result = shift; 
			    warn "Got a result\n";
			    $cv->send($result) 
			});
    
    my $result = $cv->recv();
    
    if(defined($result->{'error'}) || !($result->{'results'})){
        return;
    }

    return $result;
}

sub _send_vrf_rem_command{
    my %args = @_;

    if (!defined $mq) {
        return;
    } else {
        $mq->{'topic'} = 'MPLS.FWDCTL.RPC';
    }

    my $vrf_id = $args{'vrf_id'};
    my $cv = AnyEvent->condvar;

    warn "_send_vrf_rm_command: Calling delVrf on vrf $vrf_id";
    $mq->delVrf(vrf_id => int($vrf_id), async_callback => sub {
        my $result = shift;
        $cv->send($result);
                });

    my $result = $cv->recv();

    if (defined $result->{'error'} || !defined $result->{'results'}){
        warn '_send_vrf_rem_command: Could not complete rabbitmq call to delVrf. Received no event_id';
        if (defined $result->{'error'}) {
            warn '_send_mpls_vrf_command: ' . $result->{'error'};
        }
        return undef;
    }

    return $result->{'results'}->{'status'};
}

sub _send_vrf_add_command{
    my %args = @_;

    if (!defined $mq) {
        return;
    } else {
        $mq->{'topic'} = 'MPLS.FWDCTL.RPC';
    }    

    my $vrf_id = $args{'vrf_id'};
    my $cv = AnyEvent->condvar;

    warn "_send_vrf_add_command: Calling addVrf on vrf $vrf_id";
    $mq->addVrf(vrf_id => int($vrf_id), async_callback => sub {
        my $result = shift;
        $cv->send($result);
                });

    my $result = $cv->recv();

    if (defined $result->{'error'} || !defined $result->{'results'}){
        warn '_send_vrf_add_command: Could not complete rabbitmq call to addVrf. Received no event_id';
        if (defined $result->{'error'}) {
            warn '_send_mpls_vrf_command: ' . $result->{'error'};
        }
        return undef;
    }

    return $result->{'results'}->{'status'};
}

sub _send_mpls_add_command {
    my %args = @_;

    if (!defined $mq) {
	return;
    } else {
	$mq->{'topic'} = 'MPLS.FWDCTL.RPC';
    }

    my $circuit_id = $args{'circuit_id'};
    my $cv = AnyEvent->condvar;

    warn "_send_mpls_add_command: Calling addVlan on circuit $circuit_id";
    $mq->addVlan(circuit_id => int($circuit_id), async_callback => sub {
        my $result = shift;
        $cv->send($result);
    });

    my $result = $cv->recv();

    if (defined $result->{'error'} || !defined $result->{'results'}){
	warn '_send_mpls_add_command: Could not complete rabbitmq call to addVlan. Received no event_id';
	if (defined $result->{'error'}) {
	    warn '_send_mpls_add_command: ' . $result->{'error'};
	}
        return undef;
    }

    return $result->{'results'}->{'status'};
}

sub _send_add_command {
    my %args = @_;

    my $circuit_id = $args{'circuit_id'};
    my $force_reprovision = $args{'force_reprovision'} || 0;

    my $result = undef;
    my $err    = undef;

    if (!defined $mq) {
        $err = "Couldn't create RabbitMQ client.";
	return;
    } else {
	$mq->{'topic'} = 'OF.FWDCTL.RPC';
    }

    my $cv = AnyEvent->condvar;

    $mq->addVlan(circuit_id => int($circuit_id),
                 force_reprovision => $force_reprovision,
		 async_callback => sub {
		     my $result = shift;
		     $cv->send($result);
		 });

    $result = $cv->recv();

    warn "_send_add_command.addVlan: " . Dumper($result);

    if (!defined $result) {
        $err = "Error occurred while calling addVlan: Couldn't contact FWDCTL via RabbitMQ.";
        return ($result, $err);
    }
    if (defined $result->{'error'}) {
        $err = "Error occured while calling addVlan: $result->{'error'}";
        return ($result, $err);
    }

    return $result->{'results'}->{'status'};
}

sub _send_mpls_remove_command {
    my %args = @_;

    if (!defined $mq) {
	return;
    } else {
	$mq->{'topic'} = 'MPLS.FWDCTL.RPC';
    }

    my $circuit_id = $args{'circuit_id'};
    my $cv = AnyEvent->condvar;

    $mq->deleteVlan(circuit_id => int($circuit_id),
		    async_callback => sub {
			my $result = shift;
			$cv->send($result)
		    });
    
    my $result = $cv->recv();
    if($result->{'error'} || !($result->{'results'})){
        warn "Error occured while calling mpls_remove_command: " . $result->{'error'};
        return undef;
    }

    return $result->{'results'}->{'status'};
}

sub _send_remove_command {
    my %args = @_;

    my $circuit_id = $args{'circuit_id'};

    my $result = undef;
    my $err    = undef;

    if (!defined $mq) {
        $err = "Couldn't create RabbitMQ client.";
	return ($result, $err);
    } else {
	$mq->{'topic'} = 'OF.FWDCTL.RPC';
    }

    my $cv = AnyEvent->condvar;

    $mq->deleteVlan(circuit_id     => int($circuit_id),
		    async_callback => sub {
			my $result = shift;
			$cv->send($result);
		    });

    $result = $cv->recv();

    if (!defined $result) {
        $err = "Error occurred while calling deleteVlan: Couldn't contact FWDCTL via RabbitMQ.";
        return ($result, $err);
    }
    if (defined $result->{'error'}) {
        $err = "Error occured while calling deleteVlan: $result->{'error'}";
        return ($result, $err);
    }

    return ($result->{'results'}->{'status'}, $err);
}

sub _send_mpls_update_cache{
    my %args = @_;

    if(!defined($args{'circuit_id'})){
        $args{'circuit_id'} = -1;
    }

    my $err = undef;

    if (!defined $mq) {
        $err = "Couldn't create RabbitMQ client.";
        return;
    } else {
        $mq->{'topic'} = 'MPLS.FWDCTL.RPC';
    }
    my $cv = AnyEvent->condvar;
    $mq->update_cache(circuit_id => $args{'circuit_id'},
                      async_callback => sub {
                          my $result = shift;
                          $cv->send($result);
                      });

    my $result = $cv->recv();
    warn Dumper($result);

    if (!defined $result) {
        warn "Error occurred while calling update_cache: Couldn't contact MPLS.FWDCTL via RabbitMQ.";
        return undef;
    }
    if (defined $result->{'error'}) {
        warn "Error occurred while calling update_cache: $result->{'error'}";
        return undef;
    }
    if (defined $result->{'results'}->{'error'}) {
        warn "Error occured while calling update_cache: " . $result->{'results'}->{'error'};
        return undef;
    }

    return $result->{'results'}->{'status'};
}

sub _send_update_cache{
    my %args = @_;
    if(!defined($args{'circuit_id'})){
        $args{'circuit_id'} = -1;
    }

    my $err = undef;

    if (!defined $mq) {
        $err = "Couldn't create RabbitMQ client.";
	return;
    } else {
	$mq->{'topic'} = 'OF.FWDCTL.RPC';
    }

    my $cv = AnyEvent->condvar;
    $mq->update_cache(circuit_id => $args{'circuit_id'},
		      async_callback => sub {
			  my $result = shift;
			  $cv->send($result);
		      });

    my $result = $cv->recv();
    warn Dumper($result);

    if (!defined $result) {
        warn "Error occurred while calling update_cache: Couldn't contact FWDCTL via RabbitMQ.";
        return undef;
    }
    if (!defined $result->{'results'}) {
        warn "Something terrible happened with rabbitmq: " . Dumper($result);
        return undef;
    }
    if (defined $result->{'results'}->{'error'}) {
        warn "Error occured while calling update_cache: " . $result->{'results'}->{'error'};
        return undef;
    }

    return $result->{'results'}->{'status'};
}

sub remove_vrf {
    my ($method, $args) = @_;
    my $results;

    my $start = [gettimeofday];

    $results->{'results'} = [];

    my $workgroup_id = $args->{'workgroup_id'}{'value'};
    my $vrf_id = $args->{'vrf_id'}{'value'} || undef;
    my $remove_time = $args->{'provision_time'}{'value'};

    my $user_id = $db->get_user_id_by_auth_name(auth_name => $ENV{'REMOTE_USER'});

    my $user = $db->get_user_by_id(user_id => $user_id)->[0];

    if ($user->{'type'} eq 'read-only') {
        warn "You are a read-only user and unable to provision.";
        $method->set_error("You are a read-only user and unable to provision.");
        return;
    }

    my $vrf = OESS::VRF->new( vrf_id => $vrf_id, db => $db);
    if(!defined($vrf)){
        push(@{$results->{'results'}},{success => 0, vrf_id => $vrf_id});
        return $results;
    }

    if($vrf->{'state'} ne 'active'){
        push(@{$results->{'results'}},{success => 0, vrf_id => $vrf_id, error => "VRF is not active, unable to remove"});
        return $results;
    }

    my $res = _send_vrf_rem_command( vrf_id => $vrf_id);
    
    push(@{$results->{'results'}},{success => $res, vrf_id => $vrf_id});    
    return $results;
}

sub provision_vrf {
    my ($method, $args) = @_;
    my $results;
    
    my $start = [gettimeofday];
    
    $results->{'results'} = [];
    
    my $workgroup_id = $args->{'workgroup_id'}{'value'};
    my $vrf_id = $args->{'vrf_id'}{'value'} || undef;
    my $description = $args->{'description'}{'value'};
    my $name = $args->{'name'}{'value'};
    my $provision_time = $args->{'provision_time'}{'value'};
    my $remove_time = $args->{'provision_time'}{'value'};
    my $prefix_limit = $args->{'prefix_limit'}{'value'};
    my $endpoints = $args->{'endpoint'}{'value'};
    
    my $user_id = $db->get_user_id_by_auth_name(auth_name => $ENV{'REMOTE_USER'});
    
    my $user = $db->get_user_by_id(user_id => $user_id)->[0];

    if ($user->{'type'} eq 'read-only') {
        warn "You are a read-only user and unable to provision.";
        $method->set_error("You are a read-only user and unable to provision.");
        return;
    }
    
    my @nodes;
    my @interfaces;
    my @vlans;
    
    my @endpoints;
    foreach my $ep (@$endpoints){
	warn "Endpoints: $ep\n";
	eval{
	    my $decoded = decode_json($ep);
	    warn Dumper($decoded);
	    push(@endpoints, $decoded);
	};

    }

    foreach my $endpoint (@endpoints){
        push(@nodes, $endpoint->{'node'});
        push(@interfaces, $endpoint->{'interface'});
        push(@vlans, $endpoint->{'tag'});
    }
    
    warn Dumper(@endpoints);

    #yes I know this is not a circuit, however the same permissions exist!
    #so we can validate the circuit is valid (ie... we have all the permissions)
    my ($status,$err) = $db->validate_circuit(
        links => [],
        backup_links => [],
        nodes => \@nodes,
        interfaces => \@interfaces,
        vlans => \@vlans
    );    

    if (!$status){
        warn "Couldn't validate circuit: " . $err;
        $method->set_error("Couldn't validate circuit: " . $err);
        return;
    }

     if(!defined($vrf_id) || $vrf_id == -1){
         #create new VRF

         #first create the initial VRF record
         $db->_start_transaction();

	 #warn Dumper($name);
	 #warn Dumper($description);
	 #warn Dumper($workgroup_id);
	 #warn Dumper($user_id);

         my $vrf_id = $db->_execute_query("insert into vrf (name, description, workgroup_id, created, created_by, last_modified, last_modified_by, state) VALUES (?,?,?,unix_timestamp(now()), ?, unix_timestamp(now()), ?, 'active')", [$name, $description,$workgroup_id, $user_id, $user_id]);
         if(!defined($vrf_id)){
             my $error = $db->get_error();
             $method->set_error("Unable to create VRF: " . $error);
             $db->_rollback();
             return;
         }

         foreach my $ep (@endpoints){
             my $interface_id = $db->get_interface_id_by_names( interface => $ep->{'interface'}, node => $ep->{'node'} );

             if(!defined($interface_id)){
                 $db->_rollback();
                 $method->set_error("Unable to find interface: " . $ep->{'interface'} . " on node " . $ep->{'node'});
                 return;
             }

             if(!defined($ep->{'tag'}) || !defined($ep->{'bandwidth'})){
                 $db->_rollback();
                 $method->set_error("VRF Endpoints require both VLAN and Bandwidth fields to be specified");
                 return;
             }


             my $vrf_ep_id = $db->_execute_query("insert into vrf_ep (interface_id, tag, bandwidth, vrf_id, state) VALUES (?,?,?,?,?)",[$interface_id, $ep->{'tag'}, $ep->{'bandwidth'}, $vrf_id, 'active']);
             if(!defined($vrf_ep_id)){
                 my $error = $db->get_error();
         	$method->set_error("Unable to add VRF Endpoint: " . $error);
         	$db->_rollback();
         	return;
             }
             
             foreach my $bgp (@{$ep->{'peerings'}}){
                 warn Dumper($bgp);
                 my $res = $db->_execute_query("insert into vrf_ep_peer (vrf_ep_id, peer_ip, local_ip, peer_asn, md5_key, state) VALUES (?,?,?,?,?,?)",[$vrf_ep_id, $bgp->{'peer_ip'}, $bgp->{'local_ip'}, $bgp->{'asn'}, $bgp->{'key'}, 'active']);
                 if(!defined($res)){
                     my $error = $db->get_error();
                     $method->set_error("Uanble to add VRF Endpoint peer: " . $error);
                     $db->_rollback();
                     return;
                 }
             }
         }
         
         $db->_commit();
         
         my $vrf = OESS::VRF->new( vrf_id => $vrf_id, db => $db);
         if(!defined($vrf)){
             push(@{$results->{'results'}},{success => 0, vrf_id => $vrf_id});
             return $results;
         }

         my $res = _send_vrf_add_command( vrf_id => $vrf_id);
         

         push(@{$results->{'results'}},{success => $res, vrf_id => $vrf_id});
         
     }else{
         #edit existing VRF
         
     }

    return $results;

}

=head2 provision_circuit

=cut

sub provision_circuit {
    my ($method, $args) = @_;
    my $results;

    warn 'provision_circuit: calling';

    my $start = [gettimeofday];

    $results->{'results'} = [];
    my $output;

    my $workgroup_id = $args->{'workgroup_id'}{'value'};
    my $external_id  = $args->{'external_identifier'}{'value'} || undef;

    my $circuit_id  = $args->{'circuit_id'}{'value'} || undef;
    my $description = $args->{'description'}{'value'};

    #my $type = $args->{'type'}{'value'} || "openflow";

    # TEMPORARY HACK UNTIL OPENFLOW PROPERLY SUPPORTS QUEUING. WE CANT
    # DO BANDWIDTH RESERVATIONS SO FOR NOW ASSUME EVERYTHING HAS 0 BANDWIDTH RESERVED
    my $bandwidth   = 0;

    my $provision_time = $args->{'provision_time'}{'value'};
    my $remove_time    = $args->{'remove_time'}{'value'};

    my $restore_to_primary = $args->{'restore_to_primary'}{'value'} || 0;
    my $static_mac = $args->{'static_mac'}{'value'} || 0;

    my $links         = $args->{'link'}{'value'} || [];
    my $backup_links  = $args->{'backup_link'}{'value'} || [];
    my $nodes         = $args->{'node'}{'value'} || [];
    my $interfaces    = $args->{'interface'}{'value'} || [];
    my $tags          = $args->{'tag'}{'value'} || [];
    my $mac_addresses = $args->{'mac_address'}{'value'} || [];
    my $endpoint_mac_address_nums = $args->{'endpoint_mac_address_num'}{'value'} || [];
    my $loop_node     = $args->{'loop_node'}{'value'};
    my $state         = $args->{'state'}{'value'} || 'active';
    my $remote_nodes  = $args->{'remote_node'}{'value'} || [];
    my $remote_tags   = $args->{'remote_tag'}{'value'} || [];
    my $remote_url    = $args->{'remote_url'}{'value'};
    my $remote_requester = $args->{'remote_requester'}{'value'};

    my $rabbit_mq_start = [gettimeofday];

    my $log_client = OESS::RabbitMQ::Client->new( topic    => 'OF.FWDCTL.event',
                                                  timeout  => 15 );
    if (!defined $log_client) {
        warn "Couldn't create RabbitMQ client.";
        $method->set_error("Couldn't create RabbitMQ client.");
        return;
    }

    my $after_rabbit_mq = [gettimeofday];
    warn "Time to create rabbitMQ: " . tv_interval($rabbit_mq_start, $after_rabbit_mq);

    my $workgroup = $db->get_workgroup_by_id( workgroup_id => $workgroup_id );
    if (!defined $workgroup) {
        warn "unable to find workgroup $workgroup_id";
	$method->set_error("unable to find workgroup $workgroup_id");
	return;
    } elsif ($workgroup->{'name'} eq 'Demo') {
        warn "Sorry this is a demo account, and can not actually provision.";
        $method->set_error("Sorry this is a demo account, and can not actually provision.");
	return;
    } elsif ($workgroup->{'status'} eq 'decom') {
        warn "The selected workgroup is decomissioned and unable to provision.";
	$method->set_error("The selected workgroup is decomissioned and unable to provision.");
	return;
    }

    my $user_id = $db->get_user_id_by_auth_name(auth_name => $ENV{'REMOTE_USER'});

    my $user = $db->get_user_by_id(user_id => $user_id)->[0];
    if ($user->{'type'} eq 'read-only') {
        warn "You are a read-only user and unable to provision.";
        $method->set_error("You are a read-only user and unable to provision.");
        return;
    }

    my ($status,$err) = $db->validate_circuit(
	links => $links,
	backup_links => $backup_links,
	nodes => $nodes,
	interfaces => $interfaces,
        vlans => $tags
    );
    if (!$status){
	warn "Couldn't validate circuit: " . $err;
	$method->set_error("Couldn't validate circuit: " . $err);
	return;
    }

    if ( !$circuit_id || $circuit_id == -1 ) {
        #Register with DB
	warn 'provision_circuit: adding new circuit to the database';

	my $before_provision = [gettimeofday];

        $output = $db->provision_circuit(
            description    => $description,
            remote_url => $remote_url,
            remote_requester => $remote_requester,
            bandwidth      => $bandwidth,
            provision_time => $provision_time,
            remove_time    => $remove_time,
            links          => $links,
            backup_links   => $backup_links,
            nodes          => $nodes,
            interfaces     => $interfaces,
            tags           => $tags,
            mac_addresses  => $mac_addresses,
            endpoint_mac_address_nums  => $endpoint_mac_address_nums,
            user_name      => $ENV{'REMOTE_USER'},
            workgroup_id   => $workgroup_id,
            external_id    => $external_id,
            restore_to_primary => $restore_to_primary,
            static_mac => $static_mac,
            state => $state
        );
        if (!defined $output) {
            my $err = $db->get_error();
            warn $err;
            $method->set_error($err);
            return;
        }

        my $circuit = OESS::Circuit->new( circuit_id => $output->{'circuit_id'},
                                          db => $db);
        if(!defined($circuit)){
            $method->set_error("Unable to provision circuit");
            return;
        }
        my $type = $circuit->get_type();

	my $after_provision = [gettimeofday];
	warn "Time in DB: " . tv_interval( $before_provision, $after_provision);

        if(defined($output) && ($provision_time <= time()) && ($state eq 'active' || $state eq 'scheduled' || $state eq 'provisioned')) {

	    if ($type eq 'openflow') {
		warn 'provision_circuit: sending add command to openflow controller';

		my $before_add_command = [gettimeofday];
		
		my ($result, $err) = _send_add_command( circuit_id => $output->{'circuit_id'} );

		my $after_add_command = [gettimeofday];

		warn 'provision_circuit: received response to add command from openflow controller';
		warn "Time waiting for add: " . tv_interval( $before_add_command, $after_add_command);

                if (defined $err || $result == 0) {
                    # failure, remove the circuit now
                    $err = "provision_circuit: response from openflow controller was undef. Couldnt talk to fwdctl: $err";
                    warn "$err";
                    $output->{'warning'} = $err;
		    $method->set_error($err);

		    warn 'provision_circuit: sending remove command to openflow controller after provisioning failure';
		    remove_circuit($method, {
                        circuit_id   => {value => $output->{'circuit_id'}},
                        force        => {value => 1},
                        remove_time  => {value => -1},
                        type         => {value => $type},
                        workgroup_id => {value => $workgroup_id}
                    });
		    return;
		}
	    }

	    if($type eq 'mpls'){
		warn 'provision_circuit: sending add command to mpls controller';
		my $before_add_command = [gettimeofday];

                my $result = _send_mpls_add_command( circuit_id => $output->{'circuit_id'} );
                my $err    = undef;

                my $after_add_command = [gettimeofday];

		warn 'provision_circuit: received response to add command from mpls controller';
                warn "Time waiting for add: " . tv_interval( $before_add_command, $after_add_command);

                if (!defined $result || $result == 0) {
                    # failure, remove the circuit now
		    $err = "provision_circuit: response from mpls controller was undef. Couldn't talk to fwdctl: $err";
                    warn "$err";
                    $output->{'warning'} = $err;
                    $method->set_error($err);

                    warn 'provision_circuit: sending remove command to mpls controller after provisioning failure';
                    remove_circuit($method, {
                        circuit_id   => {value => $output->{'circuit_id'}},
                        force        => {value => 1},
                        remove_time  => {value => -1},
                        type         => {value => $type},
                        workgroup_id => {value => $workgroup_id}
                    });

                    return;
                }
            }

            #if we're here we've successfully provisioned onto the network, so log notification.
            if (defined $log_client) {
		warn 'provision_circuit: logging circuit event';
                eval{
                    my $circuit_details = $db->get_circuit_details( circuit_id => $output->{'circuit_id'} );
                    $circuit_details->{'status'} = 'up';
                    $circuit_details->{'reason'} = 'provisioned';
                    $circuit_details->{'type'} = 'provisioned';
                    $log_client->circuit_notification(type      => 'provisioned',
                                                      link_name => 'n/a',
                                                      affected_circuits => [$circuit_details],
                                                      no_reply  => 1);
                };
                if ($@) {
                    # This probably isn't a critical error, but should
                    # definitely be logged.
                    warn "$@";
                }
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
            links          => $links,
            backup_links   => $backup_links,
            nodes          => $nodes,
            interfaces     => $interfaces,
            tags           => $tags,
            mac_addresses  => $mac_addresses,
            endpoint_mac_address_nums  => $endpoint_mac_address_nums,
            user_name      => $ENV{'REMOTE_USER'},
            user_id        => $user_id,
            workgroup_id   => $workgroup_id,
            do_external    => 0,
            static_mac => $static_mac,
            do_sanity_check => 0,
            loop_node => $loop_node,
            state  => $state
        );

        my $circuit = OESS::Circuit->new( circuit_id => $circuit_id,
                                          db => $db);
        if(!defined($circuit)){
            $method->set_error("Unable to find circuit: " . $circuit_id);
            return;
        }
        my $type = $circuit->get_type();
        $edit_circuit_args{'type'} = $type;

        # Edit Existing Circuit
        # verify is allowed to modify circuit ISSUE=7690
        # and perform all other sanity checks on circuit 10278
        if (!$db->circuit_sanity_check(%edit_circuit_args)) {
            $method->set_error( $db->get_error() );
            return;
        }

        if ($state eq 'scheduled' && $provision_time > time) {
            $edit_circuit_args{'end_time'}   = -1;
            $edit_circuit_args{'name'}       = $description;

            my $output = $db->_add_edit_event(\%edit_circuit_args);
            if (!$output) {
                $method->set_error( $db->get_error() );
                return;
            }

            $results->{'results'} = [ { success => 1 } ];
            return $results;
        }

        # remove flows on switch 
	if ($type eq 'openflow') {
            my ($result, $err) = _send_remove_command( circuit_id => $circuit_id );
            if (defined $err) {
                warn "$err";
                $method->set_error($err);
                return;
            }
	    if ($result == 0) {
		$method->set_error("Unable to remove circuit. Please check your logs or contact your server adminstrator for more information. Circuit has been left in the database.");
		return;
	    }

	    # modify database entry
	    $output = $db->edit_circuit(%edit_circuit_args);
	    if (!$output) {
		$method->set_error( $db->get_error() );
		return;
	    }

	    if ($state eq 'active' || $state eq 'looped' || $state eq 'provisioned') {
                warn "output before send_add: ".Dumper($output);
		($result, $err) = _send_add_command( circuit_id => $output->{'circuit_id'} );
		if (defined $err) {
                    $err = "Unable to talk to fwdctl service: $err";
		    $output->{'warning'} = $err;
		    $method->set_error($err);
		    return;
		}
	    } else {
                $output = undef;
                warn "Unexpected circuit state '$state' was received while reprovisioning circuit. Forwarding may not work as expected";
            }
	}else{
	    my $result = _send_mpls_remove_command( circuit_id => $circuit_id );

            if ( !$result ) {
                $output->{'warning'} = "Unable to talk to fwdctl service - is it running?";
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
                    $output->{'warning'} = "Unable to talk to fwdctl service - is it running?";
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
                $log_client->circuit_notification(type      => 'modified',
                                                  link_name => 'n/a',
                                                  affected_circuits => [$circuit_details],
                                                  no_reply  => 1);
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

    my $circuit_id   = $args->{'circuit_id'}{'value'};
    my $remove_time  = $args->{'remove_time'}{'value'};
    my $workgroup_id = $args->{'workgroup_id'}{'value'};

    my $circuit = OESS::Circuit->new( circuit_id => $circuit_id,
                                      db => $db);
    if(!defined($circuit)){
        $method->set_error("Unable to find circuit: " . $circuit_id);
        return;
    }
    my $type = $circuit->get_type();
    my $results = {};
    $results->{'results'} = [];

    my $can_remove = $db->can_modify_circuit(
	circuit_id   => $circuit_id,
	username     => $ENV{'REMOTE_USER'},
	workgroup_id => $workgroup_id
    );
    if ( !defined $can_remove ) {
        $method->set_error( $db->get_error() );
	return;
    }
    if ( $can_remove < 1 ) {
	$method->set_error('Users and workgroup do not have permission to remove this circuit');
	return;
    }

    my $log_client = OESS::RabbitMQ::Client->new( topic    => 'OF.FWDCTL.event',
                                                  timeout  => 15 );
    if ( !defined($log_client) ) {
        $method->set_error("Internal server error occurred. Message queue connection failed.");
        return;
    }

    my $result;
    my $err;

    # removing it now, otherwise we'll just schedule it for later
    if ( $remove_time && $remove_time <= time() ) {
        if ($type eq 'openflow') {
            ($result, $err) = _send_remove_command( circuit_id => $circuit_id );
            if (defined $err) {
                warn "$err";
                $method->set_error($err);
		if ( !$args->{'force'}{'value'} ) {
		    return;
		}
            }
        } else {
            $result = _send_mpls_remove_command( circuit_id => $circuit_id );
        }

        if ( !defined $result) {
            warn "Unable to talk to fwdctl service - is it running?";
            $method->set_error("Unable to talk to fwdctl service - is it running?");
	    if ( !$args->{'force'}{'value'} ) {
		return;
	    }
        }

        if ( $result == 0) {
            warn "Unable to remove circuit. Please check your logs or contact your server adminstrator for more information. Circuit has been left in the database";
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

    if($type eq 'openflow'){
        _send_update_cache( circuit_id => $circuit_id);
    }else{
        _send_mpls_update_cache( circuit_id => $circuit_id );
    }

    if ( !defined $output ) {
        $err = $db->get_error();
        warn "$err";
        $method->set_error($err);
	return;
    } elsif ($remove_time <= time() ) {
        #only send removal event if it happened now, not if it was scheduled to happen later.
        #DBUS Log removal event
        eval{
            my $circuit_details = $db->get_circuit_details( circuit_id => $output->{'circuit_id'} );
            $circuit_details->{'status'} = 'removed';
            $circuit_details->{'reason'} = 'removed by ' . $ENV{'REMOTE_USER'};
            $circuit_details->{'type'} = 'removed';
            $log_client->circuit_notification(type      => 'removed',
                                              link_name => 'n/a',
                                              affected_circuits => [$circuit_details],
                                              no_reply  => 1);
        };
        if ($@) {
            # This probably isn't a critical error, but should
            # definitely be logged.
            warn "$@";
        }
    } else { # We successfully put in scheduled removal
        $result = 1;
    }

    return {results => [ { success => $result } ]};
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
        my $success     = undef;
        my $add_success = undef;
        my $err         = undef;

	($success, $err) = _send_remove_command(circuit_id => $circuit_id);
        if (defined $err) {
            my $error_text = "Error sending circuit removal request to controller, please try again or contact your Systems Administrator: $err";
            $method->set_error($error_text);
        }

	($add_success, $err) = _send_add_command(circuit_id => $circuit_id, force_reprovision => 1);
        if (defined $err) {
            my $error_text = "Error sending circuit provision request to controller, please try again or contact your Systems Administrator: $err";
            $method->set_error($error_text);
	    return {results => {status => 0} ,error => 1, error_message => $error_text};
	}
    } else {
        my $success= _send_mpls_remove_command(circuit_id => $circuit_id);
        if (!$success) {
            $method->set_error('Error sending circuit removal request to controller, please try again or contact your Systems Administrator');
        }

	#sleep(30);

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


    my $log_client = OESS::RabbitMQ::Client->new( topic    => 'OF.FWDCTL.event',
                                                  timeout  => 15 );
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
            my $result = _fail_over( circuit_id => $circuit_id, workgroup_id => $workgroup_id );
            if ( !defined($result) ) {
                $method->set_error('Unable to change the path');
		return {results => [{success => 0, alt_path_down => 0}], error => {message => "Unable to communicate with FWDCTL"}};
            }

            if ( $result == 0 ) {
                $method->set_error('Unable to change the path');
                return {results => [{success => 0, alt_path_down => 0}], error => {message => "Failure changing path"}};
            }

            my $circuit_details = $db->get_circuit_details( circuit_id => $circuit_id );

            if ($is_up) {
                eval {
                    $circuit_details->{'status'} = 'up';
                    $circuit_details->{'reason'} = "user " . $ENV{'REMOTE_USER'} . " forced the circuit to change to the alternate path";
                    $circuit_details->{'type'} = 'change_path';
                    $log_client->circuit_notification(type      => 'change_path',
                                                      link_name => 'n/a',
                                                      affected_circuits => [$circuit_details],
                                                      no_reply  => 1);

                };
                warn $@ if $@;
            } elsif ($forced) {
                eval {
                    $circuit_details->{'status'} = 'down';
                    $circuit_details->{'reason'} = "user " . $ENV{'REMOTE_USER'} . " forced the circuit to change to the alternate path which is down!";
                    $circuit_details->{'type'} = 'change_path';
                    $log_client->circuit_notification(type      => 'change_path',
                                                      link_name => 'n/a',
                                                      affected_circuits => [$circuit_details],
                                                      no_reply  => 1);
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
