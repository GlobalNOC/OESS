#!/usr/bin/perl

use strict;
use warnings;

use GRNOC::WebService::Method;
use GRNOC::WebService::Dispatcher;
use OESS::DB;
# use OESS::Interface;


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

    return {
        results => [
            { id => 1, name => 'show vrf' }
        ]
    };
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

    return {
        results => [
            'user@mx960-2-re1> show route instance OESS-L2VPN-16690 
Instance             Type
         Primary RIB                                     Active/holddown/hidden
OESS-L2VPN-16690     l2vpn non-forwarding 
         OESS-L2VPN-16690.l2vpn.0                        2/0/0
         OESS-L2VPN-16690.l2id.0                         2/0/0

'
        ]
    };
}

$svc->handle_request();
