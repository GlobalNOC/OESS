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
$method->add_input_parameter(
    name => "type",
    pattern => $GRNOC::WebService::Regex::TEXT,
    required => 0,
    description => "Type of commands to get"
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
    name => "workgroup_id",
    pattern => $GRNOC::WebService::Regex::INTEGER,
    required => 1,
    description => "ID of current user's workgroup"
);
$method->add_input_parameter(
    name => "node",
    pattern => $GRNOC::WebService::Regex::TEXT,
    required => 0,
    description => ""
);
$method->add_input_parameter(
    name => "interface",
    pattern => $GRNOC::WebService::Regex::TEXT,
    required => 0,
    description => ""
);
$method->add_input_parameter(
    name => "unit",
    pattern => $GRNOC::WebService::Regex::TEXT,
    required => 0,
    description => ""
);
$method->add_input_parameter(
    name => "peer",
    pattern => $GRNOC::WebService::Regex::TEXT,
    required => 0,
    description => ""
);
$svc->register_method($method);


sub get_commands {
    my $method = shift;
    my $params = shift;

    my $type = $params->{'type'}{'value'};

    my $result = OESS::DB::Command::fetch_all(db => $db);

    return { results => $result };
}

sub run_command {
    my $method = shift;
    my $params = shift;

    my $command_id   = $params->{command_id}{value};
    my $workgroup_id = $params->{workgroup_id}{value};

    my $cmd = OESS::DB::Command::fetch(db => $db, command_id => $command_id);
    if (!defined $cmd) {
        $method->set_error("Could not find requested command $command_id.");
        return;
    }

    my $user = OESS::DB::User::find_user_by_remote_auth(db => $db, remote_user => $ENV{'REMOTE_USER'});
    $user = OESS::User->new(db => $db, user_id =>  $user->{'user_id'});
    if (!defined $user) {
        $method->set_error("User $ENV{REMOTE_USER} is not in OESS.");
        return;
    }
    if(!$user->in_workgroup( $workgroup_id) && !$user->is_admin()){
        $method->set_error("User $ENV{REMOTE_USER} is not in workgroup.");
        return;
    }

    my $node = $params->{node}{value};
    my $intf = $params->{interface}{value};
    my $unit = $params->{unit}{value};
    my $peer = $params->{peer}{value};

    if ($cmd->{type} eq 'node') {
        if (!defined $node) {
            $method->set_error("Required parameter is missing.");
            return;
        }
    } elsif ($cmd->{type} eq 'interface') {
        if (!defined $node || !defined $intf) {
            $method->set_error("Required parameter is missing.");
            return;
        }
    } elsif ($cmd->{type} eq 'unit') {
        if (!defined $node || !defined $intf || !defined $unit) {
            $method->set_error("Required parameter is missing.");
            return;
        }
    } elsif ($cmd->{type} eq 'peer') {
        if (!defined $node || !defined $intf || !defined $unit || !defined $peer) {
            $method->set_error("Required parameter is missing.");
            return;
        }
    } else {
        $method->set_error("Unknown command type used in database.");
        return;
    }

    my $config = GRNOC::Config->new(config_file => '/etc/oess/.passwd.xml');

    my $cli_type = "junos";
    if ($node->{vendor} eq "cisco"){
	$cli_type = "ios";
    }

    my $proxy = GRNOC::RouterProxy->new(
        hostname    => $node,
        port        => 22,
        username    => $config->get('/config/@default_user')->[0],
        password    => $config->get('/config/@default_pw')->[0],
        method      => 'ssh',
        type        => $cli_type,
        maxlines    => 1000,
        timeout     => 15
    );

    my $cmd_string = '';
    my $tt = Template->new();
    $tt->process(\$cmd->{template}, { node => $node, interface => $intf, unit => $unit, peer => $peer }, \$cmd_string);

    my $result;
    if ($node->{vendor} eq 'junos') {
	$result = $proxy->junosSSH($cmd_string);
    } elsif ($node->{vendor} eq 'cisco') {
	$result = $proxy->ciscoSSH($cmd_string);
    }
    return { results => [ $result ] };
}

$svc->handle_request();
