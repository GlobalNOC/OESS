#!/usr/bin/perl

use strict;
use warnings;

use AnyEvent;

use GRNOC::WebService::Method;
use GRNOC::WebService::Dispatcher;

use OESS::AccessController::Default;
use OESS::Config;
use OESS::DB;
use OESS::Node;
use OESS::RabbitMQ::Client;
use OESS::RabbitMQ::Topic qw(discovery_topic_for_node fwdctl_topic_for_node);


my $config = new OESS::Config(config_filename => '/etc/oess/database.xml');
my $db = new OESS::DB(config_obj => $config);
my $mq = OESS::RabbitMQ::Client->new(config_obj => $config);
my $ac = new OESS::AccessController::Default(db => $db);
my $ws = new GRNOC::WebService::Dispatcher();


my $create_node = GRNOC::WebService::Method->new(
    name        => "create_node",
    description => "create_node adds a new network node to OESS",
    callback    => sub { create_node(@_) }
);
$create_node->add_input_parameter(
    name        => 'name',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => 'Name of node'
);
$create_node->add_input_parameter(
    name        => "short_name",
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => "Short name of node. Defaults to `name` if not provided."
);
$create_node->add_input_parameter(
    name        => 'longitude',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => 'Longitude of node'
);
$create_node->add_input_parameter(
    name        => 'latitude',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => 'Latitude of node'
);
$create_node->add_input_parameter(
    name        => 'vlan_range',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'VLAN range provisionable on node. Defaults to `1-4095` if not provided.'
);
$create_node->add_input_parameter(
    name        => 'ip_address',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => "IP address of node"
);
$create_node->add_input_parameter(
    name        => 'tcp_port',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => "TCP port of node"
);
$create_node->add_input_parameter(
    name        => 'make',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => "Hardware make (network vendor) of node"
);
$create_node->add_input_parameter(
    name        => 'model',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => "Hardware model of node"
);
$create_node->add_input_parameter(
    name        => 'controller',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => "Network controller of node"
);
$ws->register_method($create_node);

my $edit_node = GRNOC::WebService::Method->new(
    name        => "edit_node",
    description => "edit_node adds a new network node to OESS",
    callback    => sub { edit_node(@_) }
    );
$edit_node->add_input_parameter(
    name        => 'node_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'Node id of node'
    );
$edit_node->add_input_parameter(
    name        => 'name',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'Name of node'
    );
$edit_node->add_input_parameter(
    name        => "short_name",
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => "Short name of node. Defaults to `name` if not provided."
    );
$edit_node->add_input_parameter(
    name        => 'longitude',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'Longitude of node'
    );
$edit_node->add_input_parameter(
    name        => 'latitude',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'Latitude of node'
    );
$edit_node->add_input_parameter(
    name        => 'vlan_range',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'VLAN range provisionable on node. Defaults to `1-4095` if not provided.'
    );
$edit_node->add_input_parameter(
    name        => 'ip_address',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => "IP address of node"
    );
$edit_node->add_input_parameter(
    name        => 'tcp_port',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 0,
    description => "TCP port of node"
    );
$edit_node->add_input_parameter(
    name        => 'make',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => "Hardware make (network vendor) of node"
    );
$edit_node->add_input_parameter(
    name        => 'model',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => "Hardware model of node"
    );
$edit_node->add_input_parameter(
    name        => 'controller',
    pattern     => '^(nso|netconf)$',
    required    => 0,
    description => "Network controller of node"
    );
$ws->register_method($edit_node);

my $get_node = GRNOC::WebService::Method->new(
    name        => "get_node",
    description => "get_node returns the requested node",
    callback    => sub { get_node(@_) }
);
$get_node->add_input_parameter(
    name        => 'node_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'NodeId of node'
);
$ws->register_method($get_node);

my $get_nodes = GRNOC::WebService::Method->new(
    name        => "get_nodes",
    description => "get_nodes returns a list of all nodes",
    callback    => sub { get_nodes(@_) }
);
$ws->register_method($get_nodes);

my $delete_node = GRNOC::WebService::Method->new(
    name        => "delete_node",
    description => "delete_node decommissions the given node by its id",
    callback    => sub { delete_node(@_) }
    );
$delete_node->add_input_parameter(
    name        => 'node_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'NodeId of node'
    );
$ws->register_method($delete_node);

my $approve_diff = GRNOC::WebService::Method->new(
    name        => "approve_diff",
    description => "approve_diff approves any pending configuration changes for installation",
    callback    => sub { approve_diff(@_) }
    );
$approve_diff->add_input_parameter(
    name        => 'node_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'NodeId of node'
    );
$ws->register_method($approve_diff);

my $get_diff = GRNOC::WebService::Method->new(
    name        => "get_diff",
    description => "get_diff returns any pending configuration changes which require approval",
    callback    => sub { get_diff(@_) }
    );
$get_diff->add_input_parameter(
    name        => 'node_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'NodeId of node'
    );
$ws->register_method($get_diff);

sub create_node {
    my $method = shift;
    my $params = shift;

    $db->start_transaction;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
        
    my ($ok, $access_err) = $user->has_system_access(role => 'normal');
    if (defined $access_err){
        $method->set_error($access_err);
        $db->rollback;
        return;
    }

    my $node = new OESS::Node(
        db    => $db,
        model => {
            name       => $params->{name}{value},
            short_name => $params->{short_name}{value},
            longitude  => $params->{longitude}{value},
            latitude   => $params->{latitude}{value},
            vlan_range => $params->{vlan_range}{value},
            ip_address => $params->{ip_address}{value},
            tcp_port   => $params->{tcp_port}{value},
            make       => $params->{make}{value},
            model      => $params->{model}{value},
            controller => $params->{controller}{value}
        }
    );
    
    my $create_err = $node->create;
    if (defined $create_err) {
        $method->set_error($create_err);
        $db->rollback;
        return;
    }

    my $discovery_topic;
    my $fwdctl_topic;
    if ($node->controller eq 'netconf') {
        $discovery_topic = 'MPLS.Discovery.RPC';
        $fwdctl_topic    = 'MPLS.FWDCTL.RPC';
    } elsif ($node->controller eq 'nso') {
        $discovery_topic = 'NSO.Discovery.RPC';
        $fwdctl_topic    = 'NSO.FWDCTL.RPC';
    } else {
        $discovery_topic = 'OF.Discovery.RPC';
        $fwdctl_topic    = 'OF.FWDCTL.RPC';
    }

    my $cv = AnyEvent->condvar;

    $mq->{topic} = $fwdctl_topic;
    $mq->new_switch(
        node_id        => $node->node_id,
        async_callback => sub { $cv->send; }
    );
    $cv->recv;

    $mq->{topic} = $discovery_topic;
    $mq->new_switch(
        node_id => $node->{node_id},
        async_callback => sub { $cv->send; }
    );
    $cv->recv;
    $db->commit;
    return { results => [{ success => 1, node_id => $node->node_id }] };
}

sub edit_node {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($access_ok, $access_err) = $user->has_system_access(role => 'normal');
    if (defined $access_err) {
        $method->set_error($access_err);
        return;
    }

    my $node = new OESS::Node(
        db => $db,
        node_id => $params->{node_id}{value}
    );
    if (!defined $node) {
        $method->set_error("Couldn't find node $params->{node_id}{value}.");
        return;
    }

    if (defined $params->{name}{value}) {
        $node->name($params->{name}{value});
    }
    if (defined $params->{short_name}{value}) {
        $node->short_name($params->{short_name}{value});
    }
    if (defined $params->{latitude}{value}) {
        $node->latitude($params->{latitude}{value});
    }
    if (defined $params->{longitude}{value}) {
        $node->longitude($params->{longitude}{value});
    }
    if (defined $params->{vlan_range}{value}) {
        $node->vlan_range($params->{vlan_range}{value});
    }
    if (defined $params->{ip_address}{value}) {
        $node->ip_address($params->{ip_address}{value});
    }
    if (defined $params->{tcp_port}{value}) {
        $node->tcp_port($params->{tcp_port}{value});
    }
    if (defined $params->{make}{value}){
        $node->make($params->{make}{value});
    }
    if (defined $params->{model}{value}) {
        $node->model($params->{model}{value});
    }
    if (defined $params->{controller}{value}) {
        $node->controller($params->{controller}{value});
    }

    my $ok = $node->update;
    if (!defined $ok) {
        $ok = 0;
    }
    return { results => [{ success => $ok }] };
}


sub get_node {
    my $method = shift;
    my $params = shift;

    my $node = new OESS::Node(db => $db, node_id => $params->{node_id}{value});
    if (!defined $node) {
        $method->set_error("Couldn't find node $params->{node_id}{value}.");
        return;
    }
    return { results => [ $node->to_hash ] };
}

sub get_nodes {
    my $nodes = OESS::DB::Node::fetch_all(db => $db);
    my $result = [];
    foreach my $node (@$nodes) {
        my $obj = new OESS::Node(db => $db, model => $node);
        push @$result, $obj->to_hash;
    }
    return { results => $result };
}

sub delete_node {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($ok, $access_err) = $user->has_system_access(role => 'normal');
    if (defined $access_err) {
        $method->set_error($access_err);
        return;
    }

    my $decom_err = OESS::DB::Node::decom(db => $db, node_id => $params->{node_id}{value});
    if(defined $decom_err){
       $method->set_error($decom_err);
        return;
    }
    return { results => [{ success => 1 }] };
}

sub approve_diff {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($ok, $access_err) = $user->has_system_access(role => 'normal');
    if (defined $access_err) {
        $method->set_error($access_err);
        return;
    }

    my $node = new OESS::Node(db => $db, node_id => $params->{node_id}{value});
    if (!defined $node) {
        $method->set_error("Couldn't find node $params->{node_id}{value}.");
        return;
    }

    $node->pending_diff(0);
    $node->update;

    return { results => [{ success => 1 }] };
}

sub get_diff {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($ok, $access_err) = $user->has_system_access(role => 'read-only');
    if (defined $access_err) {
        $method->set_error($access_err);
        return;
    }

    my $node = new OESS::Node(db => $db, node_id => $params->{node_id}{value});
    if (!defined $node) {
        $method->set_error("Couldn't find node $params->{node_id}{value}.");
        return;
    }

    my ($topic, $topic_err) = fwdctl_topic_for_node($node);
    if (defined $topic_err) {
        $method->set_error($topic_err);
        return;
    }
    $mq->{topic} = $topic;

    my $cv = AnyEvent->condvar;
    $mq->get_diff_text(
        node_id        => $node->node_id,
        async_callback => sub {
            my $result = shift;
            $cv->send($result);
        }
    );
    my $result = $cv->recv;
    if (defined $result->{error}) {
        $method->set_error("$topic: $result->{error}");
        return;
    }

    return { results => [$result->{results}] };
}

$ws->handle_request;
