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

use CGI;
use JSON;
use Switch;
use Data::Dumper;

use OESS::Database;
use Net::DBus::Exporter qw(org.nddi.fwdctl);
use OESS::Topology;

my $db   = new OESS::Database();
my $topo = new OESS::Topology();

my $cgi  = new CGI;

my $username = $ENV{'REMOTE_USER'};

$| = 1;

sub main {

    if (! $db){
	send_json({"error" => "Unable to connect to database."});
	exit(1);
    }    

    my $action = $cgi->param('action');
    my $user = $db->get_user_by_id( user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];
    if ($user->{'status'} eq 'decom') {
        $action = "error";
    }
    my $output;

    switch ($action){
	
	case "get_node_status"{
	    $output = &get_node_status();
	}case "get_rules_on_node"{
	    $output = &get_rules_on_node();
	}
    case "error" {
        $output = {error => "Decom users cannot use webservices."};
    }

	else{
	    $output = {error => "Unknown action - $action"};
	}

    }
    
    send_json($output);
    
}

sub get_node_status{
    my $results;

    my $bus = Net::DBus->system;

    my $client;
    my $service;

    eval {
        $service = $bus->get_service("org.nddi.openflow");
        $client  = $service->get_object("/controller_ro");
    };

    if ($@){
        warn "Error in _connect_to_nox: $@";
        return undef;
    }

    if (! defined $client){
        return undef;
    }

    my $node_name = $cgi->param('node');
    my $node = $db->get_node_by_name( name => $node_name);

    if(!defined($node)){
	warn "Unable to find node named $node_name\n";
	return {error => "Unable to find node - $node_name "};
    }
    
    my $result = $client->get_node_connect_status($node->{'dpid'});
    $result = int($result);
    my $tmp;
    $tmp->{'results'} = {node => $node_name, status => $result};

    return $tmp;
}

sub get_rules_on_node{
    my $results;

    my $bus = Net::DBus->system;

    my $client;
    my $service;

    eval {
        $service = $bus->get_service("org.nddi.fwdctl");
        $client  = $service->get_object("/controller1");
    };

    if ($@){
        warn "Error in _connect_to_nox: $@";
        return undef;
    }

    if (! defined $client){
        return undef;
    }

    my $node_name = $cgi->param('node');
    my $node = $db->get_node_by_name( name => $node_name);

    if(!defined($node)){
        warn "Unable to find node named $node_name\n";
        return {error => "Unable to find node - $node_name "};
    }
    my $result = $client->rules_per_switch($node->{'dpid'});

    #print STDERR Dumper($result);

    $result = int($result);
    my $tmp;
    $tmp->{'results'} = {node => $node_name, rules_currently_on_switch => $result, maximum_allowed_rules_on_switch => $node->{'max_flows'}};

    return $tmp;
}


sub send_json{
    my $output = shift;
        
    print "Content-type: text/plain\n\n" . encode_json($output);
}

main();

