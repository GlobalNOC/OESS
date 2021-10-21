#!/usr/bin/perl
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
use Log::Log4perl;

use OESS::Database;
use OESS::RabbitMQ::Client;
use OESS::RabbitMQ::Topic qw(fwdctl_switch_topic_for_node);
use GRNOC::WebService;

Log::Log4perl::init('/etc/oess/logging.conf');

my $db   = new OESS::Database();

#register web service dispatcher
my $svc = GRNOC::WebService::Dispatcher->new(method_selector => ['method', 'action']);

my $mq = OESS::RabbitMQ::Client->new( topic    => 'OF.NOX.RPC',
                                      timeout  => 60 );

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

    #get_node_status
    $method = GRNOC::WebService::Method->new(
        name            => "get_mpls_node_status",
        description     => "returns JSON formatted status updates related to a Nodes connection state to the controller.",
        callback        => sub { get_mpls_node_status( @_ ) }
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

    #get_oess_status()
    $method = GRNOC::WebService::Method ->new(
        name            => 'get_oess_status',
        description     => "Returns a hash of three main services and their status as up or down",
        callback        => sub { get_oess_status( @_ ) }
        );


    #register the get_oess_status() method
    $svc->register_method($method);
}

sub get_node_status{

    my ( $method, $args ) = @_ ;
    my $results;

    if ( !defined($mq) ) {
        return;
    }

    my $node_name = $args->{'node'}{'value'};
    my $node = $db->get_node_by_name( name => $node_name);

    if(!defined($node)){
	warn "Unable to find node named $node_name\n";
	$method->set_error("Unable to find node named $node_name");
	return;
    }

    $mq->{'topic'} = 'OF.NOX.RPC';
    my $result = $mq->get_node_connect_status(dpid => int($node->{'dpid'}));
    $result = int($result->{'results'}->[0]);
    my $tmp;
    $tmp->{'results'} = {node => $node_name, status => $result};

    return $tmp;
}

sub get_mpls_node_status{
    my ( $method, $args ) = @_ ;
    my $results;

    if ( !defined($mq) ) {
        return;
    }

    my $node_name = $args->{'node'}{'value'};
    my $node = $db->get_node_by_name( name => $node_name);

    if(!defined($node)){
        warn "Unable to find node named $node_name\n";
        $method->set_error("Unable to find node named $node_name");
        return;
    }

    warn Dumper($node);

    if(!$node->{'mpls'}){
	my $tmp;
	$tmp->{'results'} = {node => $node_name, status => 0, error => "Node is not configured for mpls"};
	return $tmp;
    }

    $mq->{'topic'} = fwdctl_switch_topic_for_node(mgmt_addr => $node->{'mgmt_addr'}, tcp_port => $node->{'tcp_port'});
    my $result = $mq->is_connected();
    warn Dumper($result);
    $result = int($result->{'results'}->{'connected'});
    my $tmp;
    $tmp->{'results'} = {node => $node_name, status => $result};
    return $tmp;
}

sub get_rules_on_node{

    my ( $method, $args ) = @_ ;
    my $results;

    if ( !defined($mq) ) {
        return;
    }

    my $node_name = $args->{'node'}{'value'};
    my $node = $db->get_node_by_name( name => $node_name);

    if(!defined($node)){
        warn "Unable to find node named $node_name\n";
        $method->set_error("Unable to find node named $node_name\n");
	return;
    }

    warn Data::Dumper::Dumper($node);

    $mq->{'topic'} = 'OF.FWDCTL.RPC';
    my $result = $mq->rules_per_switch(dpid => int($node->{'dpid'}));
    warn Data::Dumper::Dumper($result);
    if (defined $result->{'error'}) {
        $method->set_error($result->{'error'});
        return;
    }

    $result = int($result->{'results'}->{'rules_on_switch'});

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

sub get_oess_status {
    my $result;
    my $serviceResult;

    return if !defined $mq;

    $mq->{'topic'} = 'MPLS.Discovery.RPC';
    $mq->{'timeout'} = 2;
    $serviceResult = $mq->is_online();
    if (defined $serviceResult->{error}) {
        push(@$result,{service_name => 'discovery', status => 'down'});
    } else {
        push(@$result,{service_name => 'discovery', status => 'up'});
    }

    $mq->{'topic'} = 'MPLS.FWDCTL.RPC';
    $serviceResult = $mq->echo();
    if (defined $serviceResult->{error}) {
        push(@$result,{service_name => 'fwdctl', status => 'down'});
    } else {
        push(@$result,{service_name => 'fwdctl', status => 'up'});
    }

    $mq->{'topic'} = 'OF.FWDCTL.RPC';
    $serviceResult = $mq->is_online();
    if (defined $serviceResult->{error}) {
       push(@$result,{service_name => 'notification', status => 'down'});
    } else {
        push(@$result,{service_name => 'notification', status => 'up'});
    }

    $mq->{'topic'} = 'OF.Notification.event';
    $serviceResult = $mq->is_online();
    if (defined $serviceResult->{error}) {
        push(@$result,{service_name => 'nsi', status => 'down'});
    } else {
        push(@$result,{service_name => 'nsi', status => 'up'});
    }

    return $result;

}

main();

