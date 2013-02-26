#!/usr/bin/perl -T
#
##----- NDDI OESS Data.cgi
##-----                                                                                  
##----- $HeadURL: svn+ssh://svn.grnoc.iu.edu/grnoc/oe-ss/frontend/trunk/webservice/data.cgi $
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----                                                                                
##----- Retrieves data about the Network for the UI
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

    my $output;

    switch ($action){
	
	case "get_maps" {
	    $output = &get_maps();
	}
	case "get_node_interfaces" {
	    $output = &get_node_interfaces();
	}
	case "get_shortest_path" {
	    $output = &get_shortest_path();
	}
	case "get_existing_circuits" {
	    $output = &get_existing_circuits();	    
	}
	case "get_circuit_details" {
	    $output = &get_circuit_details();	    
	}
	case "get_circuit_details_by_external_identifier" {
	    $output = &get_circuit_details_by_external_identifier();	    
	}
	case "get_circuit_scheduled_events" {
	    $output = &get_circuit_scheduled_events();
	}
	case "get_circuit_network_events" {
	    $output = &get_circuit_network_events();
	}
	case "is_vlan_tag_available" {
	    $output = &is_vlan_tag_available();
	}
	case "get_workgroups" {
	    $output = &get_workgroups();
	}
	case "get_workgroup_members" {
	    $output = &get_users_in_workgroup();
	}

    }
    
    send_json($output);
    
}

sub get_workgroups {
    my $results;

    my $workgroups = $db->get_workgroups_by_auth_name(auth_name => $username);

    if (! defined $workgroups){
	$results->{'error'} = $db->get_error();
    }
    else{
	$results->{'results'} = $workgroups;
    }

    return $results;
}

sub is_vlan_tag_available {
    my $results;

    $results->{'results'} = [];

    my $interface = $cgi->param('interface');
    my $node      = $cgi->param('node');
    my $vlan_tag  = $cgi->param('vlan');

    my $interface_id = $db->get_interface_id_by_names(node      => $node,
						      interface => $interface
	                                              );

    if (! defined $interface_id){
	$results->{'error'} = "Unable to find interface '$interface' on endpoint '$node'";
	return $results;
    }

    my $is_available = $db->is_external_vlan_available_on_interface(vlan          => $vlan_tag,
								    interface_id  => $interface_id);


    if ($is_available){
	push(@{$results->{'results'}}, {"available" => 1});
    }
    else{
	push(@{$results->{'results'}}, {"available" => 0});
    }

    return $results;
}

sub get_circuit_scheduled_events {
    my $results;

    my $circuit_id = $cgi->param('circuit_id');

    my $events = $db->get_circuit_scheduled_events(circuit_id => $circuit_id);

    if (! defined $events){
	$results->{'error'} = $db->get_error();
    }
    else{
	$results->{'results'} = $events;
    }

    return $results;
}

sub get_circuit_network_events {
    my $results;

    my $circuit_id = $cgi->param('circuit_id');

    my $events = $db->get_circuit_network_events(circuit_id => $circuit_id);

    if (! defined $events){
	$results->{'error'} = $db->get_error();
    }
    else{
	$results->{'results'} = $events;
    }

    return $results;
}

sub get_circuit_details {
    my $results;

    my $circuit_id = $cgi->param('circuit_id');

    my $details = $db->get_circuit_details(circuit_id => $circuit_id);

    if (!defined $details){
	$results->{'error'} = $db->get_error();
    }
    else{
	$results->{'results'} = $details;
    }

    return $results;
}

sub get_circuit_details_by_external_identifier {
    my $results;

    my $external_id = $cgi->param('external_identifier');

    my $info        = $db->get_circuit_by_external_identifier(external_identifier => $external_id);

    if (! defined $info){
	$results->{'error'} = $db->get_error();
	return $results;
    }

    my $details     = $db->get_circuit_details(circuit_id => $info->{'circuit_id'});

    if (! defined $details){
	$results->{'error'} = $db->get_error();
    }
    else {
	$results->{'results'} = $details;
    }

    return $results;
}

sub get_existing_circuits {
    
    my $results;

    my $workgroup_id = $cgi->param('workgroup_id');

    my $circuits = $db->get_current_circuits(workgroup_id => $workgroup_id);

    if (!defined $circuits){
	$results->{'error'} = $db->get_error();
    }
    else{
	$results->{'results'} = $circuits;
    }

    return $results;
}

sub get_shortest_path{

    my $results;

    $results->{'results'} = [];

    my @nodes = $cgi->param('node');

    my @links_to_avoid = $cgi->param('link');

    my $sp_links = $topo->find_path(nodes => \@nodes,
				    used_links => \@links_to_avoid);

    if (! defined $sp_links){
	$results->{'results'} = [];
	$results->{'error'}   = "No path found.";
	return $results;
    }

    foreach my $link (@$sp_links){
	push(@{$results->{'results'}}, {"link" => $link}
	    );
    }    

    return $results;

}

sub get_node_interfaces{

    my $results;

    my $node         = $cgi->param('node');
    my $workgroup_id = $cgi->param('workgroup_id');
    my $show_down   = $cgi->param('show_down') || 0;

    my $interfaces = $db->get_node_interfaces(node         => $node,
					      workgroup_id => $workgroup_id,
					      show_down    => $show_down
	                                     );

    # something went wrong
    if (!defined $interfaces){
	$results->{'error'}   = $db->get_error();
    }
    else{
	$results->{'results'} = $interfaces;
    }

    return $results;
}

sub get_maps{

    my $results;

    my $layers = $db->get_map_layers();

    if (! defined $layers){
	$results->{'error'} = $db->get_error();
    }
    else{
	$results->{'results'} = $layers;
    }

    return $results;

}

sub get_users_in_workgroup {
    my $results;

    my $workgroup_id = $cgi->param('workgroup_id');

    my $users = $db->get_users_in_workgroup( workgroup_id => $workgroup_id );

    if ( !defined $users ) {
	$results->{'error'}   = $db->get_error();
        $results->{'results'} = [];
    }
    else {
        $results->{'results'} = $users;
    }

    return $results;
}

sub send_json{
    my $output = shift;
        
    print "Content-type: text/plain\n\n" . encode_json($output);
}

main();

