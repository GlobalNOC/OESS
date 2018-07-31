#!/usr/bin/perl

use strict;
use warnings;

use GRNOC::WebService::Method;
use GRNOC::WebService::Dispatcher;
use OESS::DB;
use OESS::VRF;

use GRNOC::Config;
use GRNOC::RouterProxy;

use FileHandle;
use Template;

my $db = OESS::DB->new();
my $svc = GRNOC::WebService::Dispatcher->new();


my $method = GRNOC::WebService::Method->new(
    name => "get_commands",
    description => "returns a list of commands",
    callback => sub { get_commands(@_) }
);
$svc->register_method($method);

$method = GRNOC::WebService::Method->new(
    name => "run_command",
    description => "runs a command",
    callback => sub { run_command(@_) }
);
$method->add_input_parameter(
    name => "command_id",
    pattern => $GRNOC::WebService::Regex::INTEGER,
    required => 1,
    description => "ID of command to run"
);
$method->add_input_parameter(
    name => "vrf_id",
    pattern => $GRNOC::WebService::Regex::INTEGER,
    required => 1,
    description => "ID of VRF to run command against"
);
$svc->register_method($method);


my $commands = {
    1 => { id => 1, name => 'show version', template => 'show version' },
    2 => { id => 2, name => 'show mpls lsp brief', template => 'show mpls lsp brief' },
    3 => { id => 3, name => 'show interfaces', template => 'show interfaces [% interface %].[% unit %]' }
};


sub get_commands {
    my $method = shift;
    my $params = shift;

    my $interface_id = $params->{'interface_id'}{'value'};
    my $workgroup_id = $params->{'workgroup_id'}{'value'};

    my $result = [];
    foreach my $key (keys %$commands) {
        push @$result, $commands->{$key};
    }

    return { results => $result };
}

sub run_command {
    my $method = shift;
    my $params = shift;

    my $command_id = $params->{'command_id'}{'value'};
    my $vrf_id = $params->{'vrf_id'}{'value'};

    if (!defined $command_id) {
        $method->set_error("ERROR");
        return;
    }

    my $config = GRNOC::Config->new( config_file => '/etc/oess/.passwd.xml' );
    my $vrf = OESS::VRF->new(db => $db, vrf_id => $vrf_id);

    my $result = '';
    foreach my $ep (@{$vrf->endpoints()}) {
        my $node = $ep->{interface}->{node}->{name};
        my $intf = $ep->{interface}->{name};
        my $unit = $ep->{tag};

        my $proxy = GRNOC::RouterProxy->new(
            hostname    => $node,
            port        => 22,
            username    => $config->get('/config/@default_user')->[0],
            password    => $config->get('/config/@default_pw')->[0],
            method      => 'ssh',
            type        => 'junos',
            maxlines    => 1000,
            timeout     => 15
        );

        my $cmd_template = $commands->{$command_id}->{template};
        my $cmd = '';

        my $tt  = Template->new();
        $tt->process(\$cmd_template, { node => $node, interface => $intf, unit => $unit }, \$cmd);

        $result .= "========== $node ==========\n\n";
        $result .= $proxy->junosSSH($cmd);
    }

    return { results => [ $result ] };
}

$svc->handle_request();
