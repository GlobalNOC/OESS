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

use URI::Escape;
use MIME::Lite;
use OESS::Database;
use OESS::Topology;
use OESS::Circuit;
use Log::Log4perl;

my $db   = new OESS::Database();
my $topo = new OESS::Topology();
Log::Log4perl::init_and_watch('/etc/oess/logging.conf',10);
my $cgi = new CGI;

my $username = $ENV{'REMOTE_USER'};

$| = 1;

sub main {
    
    if ( !$db ) {
        send_json( { "error" => "Unable to connect to database." } );
        exit(1);
    }

    my $action = $cgi->param('action');

    my $output;

    switch ($action) {

        case "get_maps" {
            $output = &get_maps();
        }
        case "get_nodes" {
            $output = get_nodes();
        }
        case "get_node_interfaces" {
            $output = &get_node_interfaces();
        }
        case "get_interface" {
            $output = &get_interface();
        }
        case "get_workgroup_interfaces" {
            $output = &get_workgroup_interfaces();
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
        case "get_circuit_history" {
            $output = &get_circuit_history();
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
        case "generate_clr" {
            $output = &generate_clr();
        }
        case "get_all_node_status" {
            $output = &get_all_node_status();
        }
        case "get_all_link_status" {
            $output = &get_all_link_status();
        }
        case "get_all_resources_for_workgroup" {
            $output = &get_all_resources();
        }
        case "send_email" {
            $output = &send_message();
        }
        case "get_link_by_name" {
            $output = &get_link_by_name();
        }
        case "is_within_mac_limit" {
            $output = &is_within_mac_limit();
        }
        case "is_within_circuit_limit" {
            $output = &is_within_circuit_limit();
        }
        case "is_within_circuit_endpoint_limit" {
            $output = &is_within_circuit_endpoint_limit();
        }
        case "get_vlan_tag_range" {
            $output = &get_vlan_tag_range();
        }
        else {
            $output->{'error'}   = "Error: No Action specified";
            $output->{'results'} = [];
        }

    }

    send_json($output);

}

sub get_workgroups {
    my $results;

    my $workgroups = $db->get_workgroups_by_auth_name( auth_name => $username );

    if ( !defined $workgroups ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = $workgroups;
    }

    return $results;
}

sub get_interface {
    my $results;

    my $interface_id = $cgi->param('interface_id');

    my $interface = $db->get_interface( interface_id => $interface_id );

    if ( !defined $interface ) {
        $results->{'error'}   = $db->get_error();
        $results->{'results'} = [];
    }
    else {
        $results->{'results'} = $interface;
    }

    return $results;

}
sub get_workgroup_interfaces {
    my $results;

    my $workgroup_id = $cgi->param('workgroup_id');
    if ( !$workgroup_id ) {
        my $is_admin = $db->get_user_admin_status( 'username' => $username );
        if(!$is_admin) {
            $results->{'error'} = "Error: no workgroup_id specified";
            return $results;
        }
    }else {
        my $user_id = $db->get_user_id_by_auth_name(auth_name => $username);
        if(!$db->is_user_in_workgroup(user_id => $user_id, workgroup_id => $workgroup_id)){
            my $is_admin = $db->get_user_admin_status( 'username' => $username );
            if(!$is_admin) {
                $results->{'error'} = 'Error: you are not part of this workgroup';
                return $results;
            }
        }
    }

    my $acls = $db->get_workgroup_interfaces( workgroup_id => $workgroup_id );

    if ( !defined $acls ) {
        $results->{'error'}   = $db->get_error();
        $results->{'results'} = [];
    }
    else {
        $results->{'results'} = $acls;
    }

    return $results;
}

sub is_vlan_tag_available {
    my $results;

    $results->{'results'} = [];

    my $interface    = $cgi->param('interface');
    my $node         = $cgi->param('node');
    my $vlan_tag     = $cgi->param('vlan');
    my $workgroup_id = $cgi->param('workgroup_id');

    my $interface_id = $db->get_interface_id_by_names(
        node      => $node,
        interface => $interface
    );

    if ( !defined $interface_id ) {
        $results->{'error'} =
          "Unable to find interface '$interface' on endpoint '$node'";
        return $results;
    }

    my $is_vlan_tag_accessible = $db->_validate_endpoint(
        interface_id => $interface_id,
        vlan         => $vlan_tag,
        workgroup_id => $workgroup_id
    );
    if(!$is_vlan_tag_accessible) {
        if(!defined($is_vlan_tag_accessible)){
            return {
                results => [],
                error   => $db->get_error()
             };
        } else {
            return { results => [{ "available" => 0 }] };
        }
    }

    my $is_available = $db->is_external_vlan_available_on_interface(
        vlan         => $vlan_tag,
        interface_id => $interface_id
    );

    if ($is_available) {
        push( @{ $results->{'results'} }, { "available" => 1 } );
    }
    else {
        push( @{ $results->{'results'} }, { "available" => 0 } );
    }

    return $results;
}

sub get_vlan_tag_range {
    my $node = $cgi->param('node');
    my $interface = $cgi->param('interface');
    my $workgroup_id = $cgi->param('workgroup_id');

    my $interface_id = $db->get_interface_id_by_names(
        interface => $interface,
        node      => $node 
    ); 

    my $vlan_tag_range = $db->_validate_endpoint(
        interface_id => $interface_id,
        workgroup_id => $workgroup_id
    );

    return {
        results => [
            {vlan_tag_range => $vlan_tag_range}
        ]
    };

}

sub get_link_by_name {
    my $results;

    $results->{'results'} = [];
    
    my $name = $cgi->param('name');
    
    my $link = $db->get_link_by_name( name => $name );
    
    if ( !defined $link ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = $link;
    }

    return $results;
}

sub get_circuit_scheduled_events {
    my $results;

    my $circuit_id = $cgi->param('circuit_id');

    my $events = $db->get_circuit_scheduled_events( circuit_id => $circuit_id );

    if ( !defined $events ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = $events;
    }

    return $results;
}

sub get_circuit_history {
    my $results;

    my $circuit_id = $cgi->param('circuit_id');

    my $events = $db->get_circuit_history( circuit_id => $circuit_id );

    if ( !defined $events ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = $events;
    }

    return $results;
}

sub get_circuit_details {
    my $results;

    my $circuit_id = $cgi->param('circuit_id');

    my $ckt = OESS::Circuit->new( circuit_id => $circuit_id, db => $db);
    my $details = $ckt->get_details();

    if ( !defined $details ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = $details;
    }

    return $results;
}

sub get_circuit_details_by_external_identifier {
    my $results;

    my $external_id = $cgi->param('external_identifier');

    my $info = $db->get_circuit_by_external_identifier(
        external_identifier => $external_id );

    if ( !defined $info ) {
        $results->{'error'} = $db->get_error();
        return $results;
    }

    my $ckt = OESS::Circuit->new( circuit_id => $info->{'circuit_id'}, db => $db);
    my $details = $ckt->get_details();

    if ( !defined $details ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = $details;
    }

    return $results;
}

sub get_existing_circuits {

    my $results;

    my $workgroup_id   = $cgi->param('workgroup_id');
    my @endpoint_nodes = $cgi->param('endpoint_node_id');
    my @path_nodes     = $cgi->param('path_node_id');

    if ( !$workgroup_id ) {
        my $is_admin = $db->get_user_admin_status( 'username' => $username );
        if(!$is_admin) {
            $results->{'error'} = "Error: no workgroup_id specified";
            return $results;
        }
   }else {
        my $user_id = $db->get_user_id_by_auth_name(auth_name => $username);
        if(!$db->is_user_in_workgroup(user_id => $user_id, workgroup_id => $workgroup_id)){
            $results->{'error'} = 'Error: you are not part of this workgroup';
            return $results;
        }
    }

    my $circuits = $db->get_current_circuits(
        workgroup_id   => $workgroup_id,
        endpoint_nodes => \@endpoint_nodes,
        path_nodes     => \@path_nodes
    );

    my @res;

    foreach my $circuit (@$circuits) {
        my $ckt = OESS::Circuit->new( circuit_id => $circuit->{'circuit_id'}, db => $db);
        my $circuit_details = $ckt->get_details();
        $circuit->{'details'} = $circuit_details;
        push( @res, $circuit );
    }

    if ( !defined $circuits ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = $circuits;
    }

    return $results;
}

sub get_shortest_path {

    my $results;

    $results->{'results'} = [];

    my @nodes = $cgi->param('node');

    my @links_to_avoid = $cgi->param('link');

    my $sp_links = $topo->find_path(
        nodes      => \@nodes,
        used_links => \@links_to_avoid
    );

    if ( !defined $sp_links ) {
        $results->{'results'} = [];
        $results->{'error'}   = "No path found.";
        return $results;
    }

    foreach my $link (@$sp_links) {
        push( @{ $results->{'results'} }, { "link" => $link } );
    }

    return $results;

}

sub get_nodes {

    my $nodes = $db->get_current_nodes();

    if ( !defined($nodes) ) {
        return ( { 'error' => $db->get_error() } );
    }
    return ( { results => $nodes } );

}

sub get_node_interfaces {

    my $results;

    my $node         = $cgi->param('node');
    my $workgroup_id = $cgi->param('workgroup_id');
    my $show_down    = $cgi->param('show_down') || 0;
    my $show_trunk   = $cgi->param('show_trunk') || 0;
    my $interfaces   = $db->get_node_interfaces(
        node         => $node,
        workgroup_id => $workgroup_id,
        show_down    => $show_down,
        show_trunk   => $show_trunk
    );

    # something went wrong
    if ( !defined $interfaces ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = $interfaces;
    }

    return $results;
}

sub get_maps {

    my $results;
    my $workgroup_id = $cgi->param('workgroup_id');
    if ( !$workgroup_id ) {
        my $is_admin = $db->get_user_admin_status( 'username' => $username );
        if(!$is_admin) {
            $results->{'error'} = "Error: no workgroup_id specified";
            return $results;
        }
    }else {
        my $user_id = $db->get_user_id_by_auth_name(auth_name => $username);
        if(!$db->is_user_in_workgroup(user_id => $user_id, workgroup_id => $workgroup_id)){
            $results->{'error'} = 'Error: you are not part of this workgroup';
            return $results;
        }
    }


    my $layers = $db->get_map_layers( workgroup_id => $workgroup_id );

    if ( !defined $layers ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = $layers;
    }

    return $results;

}

sub get_users_in_workgroup {
    my $results;

    my $workgroup_id = $cgi->param('workgroup_id');
    if ( !$workgroup_id ) {
        my $is_admin = $db->get_user_admin_status( 'username' => $username );
        if(!$is_admin) {
            $results->{'error'} = "Error: no workgroup_id specified";
            return $results;
        }
    }else {
        my $user_id = $db->get_user_id_by_auth_name(auth_name => $username);
        if(!$db->is_user_in_workgroup(user_id => $user_id, workgroup_id => $workgroup_id)){
            $results->{'error'} = 'Error: you are not part of this workgroup';
            return $results;
        }
    }

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

sub generate_clr {
    my $results;

    my $circuit_id = $cgi->param('circuit_id');

    if ( !defined($circuit_id) ) {
        $results->{'error'}   = "No Circuit ID Specified";
        $results->{'results'} = [];
        return $results;
    }

    my $ckt = OESS::Circuit->new( circuit_id => $circuit_id, db => $db);

    my $circuit_clr;
    if( $cgi->param('raw') ){
        $circuit_clr = $ckt->generate_clr_raw();
    }else {
        $circuit_clr = $ckt->generate_clr();
    }
    
    if ( !defined($circuit_clr) ) {
	$results->{'error'}   = $db->get_error();
	$results->{'results'} = [];
    }
    else {
	$results->{'results'} = { clr => $circuit_clr };
    }

    return $results;
}

sub get_all_node_status {
    my $results;

    my $nodes = $db->get_current_nodes();
    
    $results->{'results'} = $nodes;

    return $results;
}

sub get_all_link_status {
    my $results;

    my $links = $db->get_current_links();

    $results->{'results'} = $links;
    return $results;
}

sub get_all_resources {
    my $results;

    my $workgroup_id = $cgi->param('workgroup_id');
    if ( !defined($workgroup_id) ) {
        $results->{'error'}   = "Did not specify workgroup id";
        $results->{'results'} = [];
    }else {
        my $user_id = $db->get_user_id_by_auth_name(auth_name => $username);
        if(!$db->is_user_in_workgroup(user_id => $user_id, workgroup_id => $workgroup_id)){
            $results->{'error'} = 'Error: you are not part of this workgroup';
            return $results;
        }
    }

    $results->{'results'} =
    $db->get_available_resources( workgroup_id => $workgroup_id );
    return $results;
}

sub is_within_circuit_limit {
    my $workgroup_id   = $cgi->param('workgroup_id');
    
    if(!$workgroup_id){
        return {
            error => "Must send workgroup_id",
            results => []
        }; 
    }
    my $return = $db->is_within_circuit_limit(
        workgroup_id => $workgroup_id
    );

    return {
        error => undef,
        results => [{
            'within_limit' => $return
        }]
    };

}

sub is_within_circuit_endpoint_limit {
    my $workgroup_id   = $cgi->param('workgroup_id');
    my $endpoint_num   = $cgi->param('endpoint_num');

    if(!defined($workgroup_id) || !defined($endpoint_num)){
        return {
            error => "Must send workgroup_id and endpoint_num",
            results => []
        };
    }
    my $return = $db->is_within_circuit_endpoint_limit(
        workgroup_id => $workgroup_id,
        endpoint_num => $endpoint_num
    );

    return {
        error => undef,
        results => [{
            'within_limit' => $return
        }]
    };
}

sub is_within_mac_limit {
    my @mac_addresses  = $cgi->param('mac_address');
    my $interface      = $cgi->param('interface');
    my $node           = $cgi->param('node');
    my $workgroup_id   = $cgi->param('workgroup_id');

    if(!@mac_addresses || !$interface || !$node || !$workgroup_id){
        return {
            error => "Must send mac_address, interface, node, and workgroup_id",
            results => []
        }; 
    }

    my $return = $db->is_within_mac_limit(
        mac_address  => \@mac_addresses,
        interface    => $interface,
        node         => $node,
        workgroup_id => $workgroup_id 
    );
    return {
        error => undef,
        results => [
            $return
        ]
    };
}

sub send_message {
    my $results;

    my $subject = $cgi->param('subject');
    my $body    = $cgi->param('body');

    my $username = $ENV{'REMOTE_USER'};

    my $message = MIME::Lite->new(
        From    => 'oess@' . $db->get_local_domain_name(),
        To      => $db->get_admin_email(),
        Subject => $subject,
        Type    => 'text/html',
        Data    => uri_unescape($body)
          . "<br><br>This was generated on behalf of $username from the OESS Application"
    );
    $message->send( 'smtp', 'localhost' );

    return { results => [ { sucess => 1 } ] };

}

sub send_json {
    my $output = shift;
    print "Content-type: text/plain\n\n" . encode_json($output);
}

main();

