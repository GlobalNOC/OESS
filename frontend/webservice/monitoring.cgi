#!/usr/bin/perl -T
#
##----- NDDI OESS Monitoring.cgi
##-----                                                                                  
##----- $HeadURL: $ 
##----- $Id: $
##----- $Date: $
##----- $LastChangedBy: $
##-----                                                                                
##----- Retrieves Monitoring information about the network
##
##-------------------------------------------------------------------------
##
##                                                                                       
## Copyright 2011 Trustees of Indiana University                                         
##                                                                                       
##   Licensed under the Apache License, Version 2.0 (the "License");                     
##  you may not use this file except in compliance with the License.                     
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

use OESS::Database;
use GRNOC::RabbitMQ::Client;
use OESS::Topology;
use GRNOC::WebService;

my $db   = new OESS::Database();
my $topo = new OESS::Topology();

#register web service dispatcher
my $svc = GRNOC::WebService::Dispatcher->new();

my $username = $ENV{'REMOTE_USER'};

$| = 1;

sub main {

    if (! $db){
	send_json({"error" => "Unable to connect to database."});
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
    
    #get_node_status
    $method = GRNOC::WebService::Method->new(
	name            => "get_node_status",
	description     => "returns JSON formatted status updates related to a Nodes connection state to the controller.",
	callback        => sub { get_node_status( @_ ) }
	);

    #add the required input parameter node
    $method->add_input_parameter(
        name            => 'node',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "Name of the node to query the status."
        );

    #register the get_node_status() method
    $svc->register_method($method);

    #get_rules_on_node()
    $method = GRNOC::WebService::Method->new(
        name            => "get_rules_on_node",
        description     => "returns the maximum allowed rules on a switch, and the total number of rules currently on the switch.",
        callback        => sub { get_rules_on_node( @_ ) }
        );

    #add the required input parameter node
    $method->add_input_parameter(
        name            => 'node',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "Name of the node to query the rules."
        );

    #register the get_rules_on_node() method
    $svc->register_method($method);

}

sub get_node_status{

    my ( $method, $args ) = @_ ;
    my $results;

    my $client  = new GRNOC::RabbitMQ::Client(
        topic => 'OF.NOX.RPC',
        exchange => 'OESS',
        user => 'guest',
        pass => 'guest',
        host => 'localhost',
        port => 5672
    );
    if ( !defined($client) ) {
        return;
    }

    my $node_name = $args->{'node'}{'value'};
    my $node = $db->get_node_by_name( name => $node_name);

    if(!defined($node)){
	warn "Unable to find node named $node_name\n";
	$method->set_error("Unable to find node named $node_name");
	return;
    }
    
    my $result = $client->get_node_connect_status(dpid => int($node->{'dpid'}));
    $result = int($result->{'results'}->[0]);
    my $tmp;
    $tmp->{'results'} = {node => $node_name, status => $result};

    return $tmp;
}

sub get_rules_on_node{

    my ( $method, $args ) = @_ ;
    my $results;

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

    my $node_name = $args->{'node'}{'value'};
    my $node = $db->get_node_by_name( name => $node_name);

    if(!defined($node)){
        warn "Unable to find node named $node_name\n";
        $method->set_error("Unable to find node named $node_name\n");
	return;
    }
    my $result = $client->rules_per_switch(dpid => int($node->{'dpid'}));
    $result = int($result->{'results'});

    my $tmp;
    $tmp->{'results'} = {node => $node_name, rules_currently_on_switch => $result, maximum_allowed_rules_on_switch => $node->{'max_flows'}};

    return $tmp;
}


sub send_json {
    my $output = shift;
    
    if (!defined($output) || !$output) {
        $output =  { "error" => "Server error in accessing webservices." };
    }
        
    print "Content-type: text/plain\n\n" . encode_json($output);
}

main();

