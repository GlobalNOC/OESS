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

sub create_node {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($ok, $access_err) = $user->has_system_access(role => 'admin');
    return (undef, $access_err) if defined $access_err;

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

    return { results => [{ success => 1, node_id => $node->node_id }] };
}

$ws->handle_request;
