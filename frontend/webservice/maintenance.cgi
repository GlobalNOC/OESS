#!/usr/bin/perl -T
#
##----- NDDI OESS maintenance.cgi
##-----
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----
##----- Provides a WebAPI to allow for maintenance of nodes and links
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
##

use strict;
use warnings;

use CGI;
use Data::Dumper;
use JSON;
use OESS::Database;
use Switch;


my $db = new OESS::Database();
my $cgi = new CGI;

$| = 1;


sub main {
    if (!$db) {
        send_json( { "error" => "Unable to connect to database." } );
        exit(1);
    }
    my $action = $cgi->param('action');
    print STDERR "action " . $action;

    my $user = $db->get_user_by_id(user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];
    if ($user->{'status'} eq 'decom') {
        $action = "error";
    }

    my $output;
    switch ($action) {
        case "nodes" {
            $output = &node_maintenances();
        }
        case "start_node" {
            if ($user->{'type'} eq 'read-only') {
              $output = {error => 'You are a read-only user and unable start or end maintenance.'};
            } else {
              $output = &start_node_maintenance();
            }
        }
        case "end_node" {
            if ($user->{'type'} eq 'read-only') {
              $output = {error => 'You are a read-only user and unable start or end maintenance.'};
            } else {
              $output = &end_node_maintenance();
            }
        }
        case "links" {
            $output = &link_maintenances();
        }
        case "start_link" {
            if ($user->{'type'} eq 'read-only') {
              $output = {error => 'You are a read-only user and unable start or end maintenance.'};
            } else {
              $output = &start_link_maintenance();
            }
        }
        case "end_link"{
            if ($user->{'type'} eq 'read-only') {
              $output = {error => 'You are a read-only user and unable start or end maintenance.'};
            } else {
              $output = &end_link_maintenance();
            }
        }
        case "error" {
            my $message = "Decommed users cannot use webservices.";
            warn $message;
            $output = { error => $message };
        } 
        else {
            my $message = "Unknown action - $action";
            warn $message;
            $output = { error => $message };
        }
    }
    send_json($output);
}

sub send_json {
    my $output = shift;
    print "Content-type: text/plain\n\n" . encode_json($output);
}

sub _execute_node_maintenance {
    my $node_id = shift;
    my $state = shift;

    my $client;
    my $service;
    my $bus = Net::DBus->system;
    eval {
        $service = $bus->get_service("org.nddi.fwdctl");
        $client  = $service->get_object("/controller1");
    };
    if ($@) {
        warn "Error in _connect_to_fwdctl: $@";
        return;
    }
    if (!defined $client) {
        warn "Issue communicating with fwdctl";
        return;
    }

    return $client->node_maintenance($node_id, $state);
}

sub node_maintenances {
    my $results;
    my $node_id = $cgi->param('node_id');

    my $data;
    if (defined $node_id) {
        $data = $db->get_node_maintenance($node_id);
    } else {
        $data = $db->get_node_maintenances();
    }

    if (!defined $data) {
        return { error => "Failed to retrieve nodes under maintenance." };
    }
    $results->{'results'} = $data;
    return $results;
}

sub start_node_maintenance {
    my $results;
    my $node_id = $cgi->param('node_id');
    my $description = $cgi->param('description');

    if (!defined $node_id) {
        return { error => "Parameter node_id must be provided." };
    }
    
    if (!defined $description) {
        $description = "";
    }

    $db->_start_transaction();
    my $data = $db->start_node_maintenance($node_id, $description);
    if (!defined $data) {
        $db->_rollback();
        return { error => "Failed to put node into maintenance mode." };
    }

    my $res = _execute_node_maintenance($node_id, "start");
    if ($res != 1) {
        $db->_rollback();
        return { error => "Failed to put node into maintenance mode." };
    }
    $db->_commit();

    $results->{'results'} = $data;
    return $results;
}

sub end_node_maintenance {
    my $results;
    my $node_id = $cgi->param('node_id');
    if (!defined $node_id) {
        return { error => "Parameter node_id must be provided." };
    }
    my $data = $db->end_node_maintenance($node_id);
    if (!defined $data) {
        return { error => "Failed to take node out of maintenance mode." };
    }
    _execute_node_maintenance($node_id, "end");

    $results->{'results'} = $data;
    return $results;
}

sub _execute_link_maintenance {
    my $link_id = shift;
    my $state = shift;

    my $client;
    my $service;
    my $bus = Net::DBus->system;
    eval {
        $service = $bus->get_service("org.nddi.fwdctl");
        $client  = $service->get_object("/controller1");
    };
    if ($@) {
        warn "Error in _connect_to_fwdctl: $@";
        return;
    }
    if (!defined $client) {
        warn "Issue communicating with fwdctl";
        return;
    }

    return $client->link_maintenance($link_id, $state);
}

sub link_maintenances {
    my $results;
    my $link_id = $cgi->param('link_id');

    my $data;
    if (defined $link_id) {
        $data = $db->get_link_maintenance($link_id);
    } else {
        $data = $db->get_link_maintenances();
    }

    if (!defined $data) {
        return { error => "Failed to retrieve links under maintenance." };
    }
    $results->{'results'} = $data;
    return $results;
}

sub start_link_maintenance {
    my $results;
    my $link_id = $cgi->param('link_id');
    my $description = $cgi->param('description');

    if (!defined $link_id) {
        return { error => "Parameter link_id must be provided." };
    }
    
    if (!defined $description) {
        $description = "";
    }

    $db->_start_transaction();
    my $data = $db->start_link_maintenance($link_id, $description);
    if (!defined $data) {
        $db->_rollback();
        return { error => "Failed to put link into maintenance mode." };
    }
    my $res = _execute_link_maintenance($link_id, "start");
    if ($res != 1) {
        $db->_rollback();
        return { error => "Failed to put link into maintenance mode." };
    }
    $db->_commit();

    $results->{'results'} = $data;
    return $results;
}

sub end_link_maintenance {
    my $results;
    my $link_id = $cgi->param('link_id');
    if (!defined $link_id) {
        return { error => "Parameter link_id must be provided." };
        return $results;
    }
    
    my $data = $db->end_link_maintenance($link_id);
    if (!defined $data) {
        return { error => "Failed to take link out of maintenance mode." };
    }
    _execute_link_maintenance($link_id, "end");

    $results->{'results'} = $data;
    return $results;
}

main();
