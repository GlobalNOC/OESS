#!/usr/bin/perl
#
##----- NDDI OESS traceroute.cgi
##-----
##----- Provides a WebAPI to allow for initiating and getting the results of a circuit traceroutes
##
##-------------------------------------------------------------------------
##
##
## Copyright 2015 Trustees of Indiana University
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
use GRNOC::RabbitMQ::Client;

use Data::Dumper;

use OESS::Database;
use OESS::Topology;
use OESS::Circuit;
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
    if ($user->{'status'} eq "decom") {
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
    
    #init_circuit_traceroute()
    $method = GRNOC::WebService::Method->new(
	name            => "init_circuit_traceroute",
	description     => "starts a trace route for a circuit.",
	callback        => sub { init_circuit_traceroute( @_ ) }
	);
    
    # add the required input parameter workgroup_id
    $method->add_input_parameter(
	name            => 'workgroup_id',
	pattern         => $GRNOC::WebService::Regex::INTEGER,
	required        => 1,
	description     => "the workgroup requesting the trace"
	); 

    #add the required input parameter circuit_id
    $method->add_input_parameter(
        name            => 'circuit_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The identifier for the circuit in the OESS database."
        );

    #add the required input parameter node.
    $method->add_input_parameter(
        name            => 'node',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "the name of the node to start the trace from."
        );

    #add the required input paramter interface.
    $method->add_input_parameter(
        name            => 'interface',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "the name of the interfaceto start the trace from."
        );

    #register the init_circuit_traceroute() method
    $svc->register_method($method);

    #get_circuit_traceroute()
    $method = GRNOC::WebService::Method->new(
        name            => "get_circuit_traceroute",
        description     => "fetches the current results for a circuit traceroute.",
        callback        => sub { get_circuit_traceroute( @_ ) }
        );

    # add the required input parameter workgroup_id
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "the workgroup requesting the trace"
        );

    #add the required input parameter circuit_id
    $method->add_input_parameter(
        name            => 'circuit_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The identifier for the circuit in the OESS database."
        );

    #register the get_circuit_traceroute() method
    $svc->register_method($method);
}
sub init_circuit_traceroute {

    my ( $method, $args ) = @_ ;
    my $results;

    $results->{'results'} = [];


    my $output;
    
    #workgroup_id, circuit_id, source_interface, are all required;
    my $workgroup_id = $args->{'workgroup_id'}{'value'};
    my $circuit_id  = $args->{'circuit_id'}{'value'};
    my $source_node = $args->{'node'}{'value'};
    my $source_intf = $args->{'interface'}{'value'};
   
    my $interface_id = $db->get_interface_id_by_names (node => $source_node,
                                                       interface => $source_intf
        );

    my $source_interface = $interface_id;

    my $ckt = OESS::Circuit->new( circuit_id => $circuit_id, db => $db);
    warn Data::Dumper::Dumper($ckt);
    if (!$ckt || $ckt->{'details'}->{'state'} ne 'active'){
        $method->set_error("User and workgroup do not have permission to traceroute this circuit");
	return;
    }

    my $endpoints = $db->get_circuit_endpoints(circuit_id => $circuit_id);
    warn Dumper ($endpoints);
    if (!$endpoints){
	$method->set_error("Could not get endpoints for circuit $circuit_id");
	return;
    }
    my $source_interface_is_endpoint=0;
    
    foreach my $endpoint (@$endpoints){
        if ($endpoint->{'interface'} eq $source_intf &&$endpoint->{'node'} eq $source_node ){
            $source_interface_is_endpoint =1;
            last;
        }
    }
    
    if ( !$source_interface_is_endpoint ){
        $method->set_error("interface $source_interface is not an endpoint of circuit $circuit_id");
	return;
    }

    my $traceroute_client  = new GRNOC::RabbitMQ::Client(
        topic => 'OF.NDDI.RPC',
        exchange => 'OESS',
        user => 'guest',
        pass => 'guest',
        host => 'localhost',
        port => 5672
    );
    if ( !defined($traceroute_client) ) {
        return {error => 'unable to talk to traceroute service'};
    }

    my $workgroup = $db->get_workgroup_by_id( workgroup_id => $workgroup_id );
    if(!defined($workgroup)){
	$method->set_error("unable to find workgroup $workgroup_id.");
	return;
    }
    elsif($workgroup->{'status'} eq 'decom'){
	$method->set_error("The selected workgroup is decomissioned and unable to provision.");
	return;
    }

    my $user = $db->get_user_by_id(user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];
         
    my $can_edit = $db->can_modify_circuit(
                                             circuit_id   => $circuit_id,
                                             username     => $ENV{'REMOTE_USER'},
                                             workgroup_id => $workgroup_id
                                            );


    if ( $can_edit < 1 ) {
	$method->set_error("User and workgroup do not have permission to traceroute this circuit");
	return;
    }

        
    my $result = $traceroute_client->init_circuit_trace($circuit_id,$source_interface);
    if ($result){
        $results->{'results'} = [{success => '1'}];
        
    }


    return $results;
}

sub get_circuit_traceroute {
    
    my ( $method, $args ) = @_ ;
    my $results;

    $results->{'results'} = [];


    my $output;

    my $workgroup_id = $args->{'workgroup_id'}{'value'};
    my $circuit_id  =  $args->{'circuit_id'}{'value'};

    my $traceroute_client  = new GRNOC::RabbitMQ::Client(
        topic => 'OF.NDDI.RPC',
        exchange => 'OESS',
        user => 'guest',
        pass => 'guest',
        host => 'localhost',
        port => 5672
    );
    if ( !defined($traceroute_client) ) {
        return {error => 'unable to talk to traceroute service'};
    }

    my $workgroup = $db->get_workgroup_by_id( workgroup_id => $workgroup_id );
    if(!defined($workgroup)){
	$method->set_error("unable to find workgroup $workgroup_id");
	return;
    }
    elsif($workgroup->{'status'} eq 'decom'){
	$method->set_error("The selected workgroup is decomissioned and unable to provision");
	return;
    }

    my $user = $db->get_user_by_id(user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];
         
    my $can_edit = $db->can_modify_circuit(
	circuit_id   => $circuit_id,
	username     => $ENV{'REMOTE_USER'},
	workgroup_id => $workgroup_id
	);


    if ( $can_edit < 1 ) {
        $method->set_error("No traceroute data found for this circuit.");
	return;
    }

    #dbus is fighting me, this is suboptimal, but dbus does not like the signature changing.    
    my $result = $traceroute_client->get_traceroute_transactions({});
    
    if ($result && $result->{$circuit_id}){
        my $node_dpid_hash = $db->get_node_dpid_hash;
        my $dpid_node_hash = {};
        #invert the hash, because we can
        foreach my $node_name (keys %$node_dpid_hash){
            $dpid_node_hash->{ $node_dpid_hash->{$node_name} } = $node_name;
        }
        $result = $result->{$circuit_id};
        delete $result->{source_endpoint};
        my @tmp_nodes = split(",",$result->{nodes_traversed});
        my @tmp_interfaces = split(",",$result->{'interfaces_traversed'});
        # replace dpid with node name
        foreach my $dpid (@tmp_nodes){
            $dpid = $dpid_node_hash->{$dpid};
        }
        
        $result->{nodes_traversed} = \@tmp_nodes;
        $result->{interfaces_traversed} = \@tmp_interfaces;
        push (@{$results->{results}}, $result);
    }
    if (!defined($result)){
        $method->set_error("No traceroute data found for this circuit");
	return;
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
