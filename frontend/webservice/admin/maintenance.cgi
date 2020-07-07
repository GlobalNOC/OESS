#!/usr/bin/perl
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


use Data::Dumper;
use JSON;
use OESS::Database;
use OESS::DB;
use OESS::DB::User;
use OESS::RabbitMQ::Client;
use Switch;
use Log::Log4perl;
use GRNOC::WebService;

Log::Log4perl::init('/etc/oess/logging.conf');

my $db = new OESS::Database();
my $db2 = new OESS::DB();
my $mq = OESS::RabbitMQ::Client->new( topic    => 'OF.FWDCTL.RPC',
                                      timeout  => 60 );

#register web service dispatcher
my $svc = GRNOC::WebService::Dispatcher->new(method_selector => ['method', 'action']);

$| = 1;


sub main {
    if (!$db) {
        send_json( { "error" => "Unable to connect to database." } );
        exit(1);
    }
    if (!$db2) {
        send_json( { "error" => "Unable to connect to database." } );
        exit(1);
    }
    if ( !$svc ){
	send_json( {"error" => "Unable to access GRNOC::WebService" });
	exit(1);
    }

    my $user = $db->get_user_by_id(user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}));
    if (!defined $user) {
        send_json({"error" => "Unable to lookup user."});
        exit(1);
    }
    $user = $user->[0];
    if ($user->{'status'} eq 'decom') {
	send_json({"error" => "Unable to lookup user."});
	exit(1);
    }
    if(!defined($user)){
        return send_json({error => "unable to find user"});
    } 
    my $authorization = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role = 'normal');
    
    if (defined $authorization) {
        return send_json($authorization);
    }

    
   


    #register the WebService Methods
    register_webservice_methods();

    #handle the WebService request.
    $svc->handle_request();
}

sub register_webservice_methods {
    
    my $method;

    #nodes()
    $method = GRNOC::WebService::Method->new(
	name            => "nodes",
	description     => "returns the node maintainence for a node",
	callback        => sub { node_maintenances( @_ ) }
	);

    #add the optional input parameter node_id
    $method->add_input_parameter(
	name            => 'node_id',
	pattern         => $GRNOC::WebService::Regex::INTEGER,
	required        => 0,
	description     => "The node ID of the node for which we need the maintainence information."
	); 

    #register the nodes() method
    $svc->register_method($method);

    #links()
    $method = GRNOC::WebService::Method->new(
        name            => "links",
        description     => "returns the links maintainence",
        callback        => sub { link_maintenances( @_ ) }
        );

    #add the optional input parameter link_id
    $method->add_input_parameter(
        name            => 'link_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "The link ID of the link for which we need the maintainence information."
        );

    #register the links() method
    $svc->register_method($method);

    #start_node
    $method = GRNOC::WebService::Method->new(
        name            => "start_node",
        description     => "starts the node maintainence for a node",
        callback        => sub { start_node_maintenance( @_ ) }
        );

    #add the required input parameter node_id
    $method->add_input_parameter(
        name            => 'node_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The node ID of the node for which user wants to start the node maintainence."
        );

    # add the optional input parameter description 
    $method->add_input_parameter(
	name            => 'description',
	pattern         => $GRNOC::WebService::Regex::TEXT,
	required        => 0,
	description     => "Brief description about the maintainence on the node."
	); 

    #register the start_node() method
    $svc->register_method($method);

    #end_node
    $method = GRNOC::WebService::Method->new(
        name            => "end_node",
        description     => "ends the  the node maintainence for a node",
        callback        => sub { end_node_maintenance( @_ ) }
        );

    #add the required input parameter node_id
    $method->add_input_parameter(
        name            => 'node_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The node ID of the node for which we want to end the maintainence."
        );

    #register the end_node() method
    $svc->register_method($method);
    
    #start_link
    $method = GRNOC::WebService::Method->new(
        name            => "start_link",
        description     => "starts the link maintainence for a link",
        callback        => sub { start_link_maintenance( @_ ) }
        );

    #add the required input parameter link_id
    $method->add_input_parameter(
        name            => 'link_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The link ID of the link for which user wants to start the node maintainence."
        );

    # add the optional input parameter description
    $method->add_input_parameter(
        name            => 'description',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 0,
        description     => "Brief description about the maintainence on the link."
        );

    #register the start_link() method
    $svc->register_method($method);

    #end_link()
    $method = GRNOC::WebService::Method->new(
	name            => "end_link",
        description     => "ends the  the link maintainence for a link.",
	callback        => sub { end_link_maintenance( @_ ) }
	);
    
    #add the required input parameter link_id
    $method->add_input_parameter(
        name            => 'link_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The link ID of the link for which we want to end the maintainence."
        );

    #register the end_link() method
    $svc->register_method($method);

}

sub send_json {
    my $output = shift;
    if (!defined($output) || !$output) {
        $output =  { "error" => "Server error in accessing webservices." };
    }
    print "Content-type: text/plain\n\n" . encode_json($output);
}

sub _execute_node_maintenance {
    my $node_id = shift;
    my $state = shift;

    if (!defined $mq ) {
        warn "Could not communicate with FWDCTL. Please check rabbitmq-server.";
        return;
    }
    return $mq->node_maintenance(node_id => int($node_id), state => $state);
}

sub node_maintenances {
    my ( $method, $args ) = @_ ;
    my $results;
    my $node_id = $args->{'node_id'}{'value'};

    my $data;
    if (defined $node_id) {
        $data = $db->get_node_maintenance($node_id);
    } else {
        $data = $db->get_node_maintenances();
    }

    if (!defined $data) {
	$method->set_error("Failed to retrieve nodes under maintenance.");
	return;
    }
    $results->{'results'} = $data;
    return $results;
}

sub start_node_maintenance {

    my ( $method, $args ) = @_ ;
    my $results;
    my $node_id = $args->{'node_id'}{'value'};
    my $description = $args->{'description'}{'value'};

    if (!defined $node_id) {
        $method->set_error("Parameter node_id must be provided.");
        return;
    }
        
    if (!defined $description) {
        $description = "";
    }

    $db->_start_transaction();
    my $data = $db->start_node_maintenance($node_id, $description);
    if (!defined $data) {
        my $err_msg = $db->get_error();
        $db->_rollback();

        if($err_msg eq OESS::Database::ERR_NODE_ALREADY_IN_MAINTENANCE) {
            $method->set_error("The node is already in maintenance mode.");
        } else {
            $method->set_error("Failed to put node into maintenance mode; Database error occurred.");
        }
	return;
    }
    $db->_commit();
    
    my $res = _execute_node_maintenance($node_id, "start");
    if (!defined $res) {
        $db->end_node_maintenance($node_id);
        $method->set_error("Failed to put node into maintenance mode; Message queue error occurred.");
        return;
    }

    if ($res->{'results'}->{'status'} != 1) {
        $db->end_node_maintenance($node_id);
        $method->set_error("Failed to put node into maintenance mode.");
        return;
    }

    $results->{'results'} = $data;
    return $results;
}

sub end_node_maintenance {
    my ( $method, $args ) = @_ ;
    my $results;
    my $node_id = $args->{'node_id'}{'value'};

    my $data = $db->end_node_maintenance($node_id);
    if (!defined $data) {
        $method->set_error("Failed to take node out of maintenance mode.");
	return;
    }
    _execute_node_maintenance($node_id, "end");

    $results->{'results'} = $data;
    return $results;
}

sub _execute_link_maintenance {
    my $link_id = shift;
    my $state = shift;

    if (!defined $mq) {
        return;
    }
    return $mq->link_maintenance(link_id => int($link_id), state => $state);
}

sub link_maintenances {
    my ( $method, $args ) = @_ ;
    my $results;
    my $link_id = $args->{'link_id'}{'value'};

    my $data;
    if (defined $link_id) {
        $data = $db->get_link_maintenance($link_id);
    } else {
        $data = $db->get_link_maintenances();
    }

    if (!defined $data) {
        $method->set_error("Failed to retrieve links under maintenance.");
	return;
    }
    $results->{'results'} = $data;
    return $results;
}

sub start_link_maintenance {
    my ( $method, $args ) = @_ ;

    my $results     = {};
    my $link_id     = $args->{'link_id'}{'value'};
    my $description = $args->{'description'}{'value'};

    if (!defined $link_id) {
        $method->set_error(error => "Parameter link_id must be provided.");
        return;
    }

    if (!defined $description) {
        $description = "";
    }

    $db->_start_transaction();
    my $data = $db->start_link_maintenance($link_id, $description);
    if (!defined $data) {
        $db->_rollback();
        $method->set_error("Failed to put link into maintenance mode. Database error occurred.");
	return;
    }
    $db->_commit();

    my $res = _execute_link_maintenance($link_id, "start");
    if (!defined $res) {
        $db->end_link_maintenance($link_id);
        $method->set_error("Failed to put link into maintenance mode; Message queue error occurred.");
        return;
    }

    if ($res->{'results'}->{'status'} != 1) {
        $db->end_link_maintenance($link_id);
        $method->set_error("Failed to put link into maintenance mode.");
        return;
    }

    $results->{'results'} = $data;
    return $results;
}

sub end_link_maintenance {

    my ( $method, $args ) = @_ ;
    my $results;
    my $link_id = $args->{'link_id'}{'value'};
    
    my $data = $db->end_link_maintenance($link_id);
    if (!defined $data) {
        $method->set_error("Failed to take link out of maintenance mode.");
	return;
    }
    _execute_link_maintenance($link_id, "end");

    $results->{'results'} = $data;
    return $results;
}

main();
