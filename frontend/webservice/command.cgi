#!/usr/bin/perl

use strict;
use warnings;

use GRNOC::WebService::Method;
use GRNOC::WebService::Dispatcher;
use OESS::DB;
use OESS::VRF;
use OESS::DB::Command;

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


sub get_commands {
    my $method = shift;
    my $params = shift;

    my $interface_id = $params->{'interface_id'}{'value'};
    my $workgroup_id = $params->{'workgroup_id'}{'value'};
    my $type = $params->{'type'}{'value'} || 'l3vpn';

    my $result = OESS::DB::Command::fetch_all(db => $db, type => $type);

    return { results => $result };
}

sub run_command {
    my $method = shift;
    my $params = shift;

    my $command_id = $params->{'command_id'}{'value'};
    my $vrf_id = $params->{'vrf_id'}{'value'};

    my $config = GRNOC::Config->new(config_file => '/etc/oess/.passwd.xml');
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

        my $cmd = OESS::DB::Command::fetch(db => $db, command_id => $command_id);
        if (!defined $cmd) {
            $method->set_error("Could not find requested command $command_id.");
            return;
        }

        my $cmd_string = '';
        my $tt = Template->new();
        $tt->process(\$cmd->{template}, { node => $node, interface => $intf, unit => $unit }, \$cmd_string);

        $result .= "========== $node ==========\n\n";
        $result .= $proxy->junosSSH($cmd_string);
    }

    return { results => [ $result ] };
}

$svc->handle_request();
