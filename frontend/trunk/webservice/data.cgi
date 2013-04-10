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

my $db   = new OESS::Database();
my $topo = new OESS::Topology();

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

sub is_vlan_tag_available {
    my $results;

    $results->{'results'} = [];

    my $interface = $cgi->param('interface');
    my $node      = $cgi->param('node');
    my $vlan_tag  = $cgi->param('vlan');

    my $interface_id = $db->get_interface_id_by_names(
        node      => $node,
        interface => $interface
    );

    if ( !defined $interface_id ) {
        $results->{'error'} =
          "Unable to find interface '$interface' on endpoint '$node'";
        return $results;
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

sub get_circuit_scheduled_events {
    my $results;

    my $circuit_id = $cgi->param('circuit_id');

    my $events = $db->get_circuit_scheduled_events( circuit_id => $circuit_id );

    if ( !defined $events ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        print STDERR Dumper($events);
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

    my $details = $db->get_circuit_details( circuit_id => $circuit_id );

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

    my $details =
      $db->get_circuit_details( circuit_id => $info->{'circuit_id'} );

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
        unless ($is_admin) {
            $results->{'error'} = "Error: no workgroup_id specified";
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
        my $circuit_details =
          $db->get_circuit_details( circuit_id => $circuit->{'circuit_id'} );
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

    my $circuit_clr = $db->generate_clr( circuit_id => $circuit_id );

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
    }
    $results->{'results'} =
      $db->get_workgroup_acls( workgroup_id => $workgroup_id );
    return $results;
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
    print STDERR Dumper($output);
    print "Content-type: text/plain\n\n" . encode_json($output);
}

main();

