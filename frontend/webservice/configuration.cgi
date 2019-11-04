#!/usr/bin/perl -I /home/aragusa/OESS/perl-lib/OESS/lib

use strict;
use warnings;

use Data::Dumper;
use DateTime;
use Digest::MD5 qw(md5_hex);
use JSON;
use Log::Log4perl;
use Template;

use GRNOC::WebService::Dispatcher;
use GRNOC::WebService::Method;

use OESS::DB;
use OESS::Database;
use OESS::Endpoint;

use OESS::DB::Circuit;
use OESS::DB::Entity;
use OESS::DB::User;

use OESS::Entity;
use OESS::User;
use OESS::VRF;


Log::Log4perl::init_and_watch('/etc/oess/logging.conf', 10);


my $db = OESS::DB->new();

my $ws = GRNOC::WebService::Dispatcher->new();

my $get = GRNOC::WebService::Method->new(
    name        => 'get',
    callback    => \&get,
    description => 'Returns a configuration generated for the layer 3 connection endpoint.'
);
$get->add_input_parameter(
    name        => 'workgroup_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'Identifier of Workgroup to filter results by.'
);
$get->add_input_parameter(
    name        => 'vrf_ep_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'Identifier of Layer 3 Connection Endpoint.'
);
$get->add_input_parameter(
    name        => 'make',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => 'Network device make (vendor)'
);
$get->add_input_parameter(
    name        => 'model',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => 'Network device model'
);
$get->add_input_parameter(
    name        => 'version',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => 'Network device firmware version'
);
$ws->register_method($get);

sub get {
    my ($method, $args) = @_;

    my $configs = {
        cisco => {
            2900 => { ios124 => 1 },
            3700 => { ios124 => 1 },
            7200 => { ios124 => 1 },
            nexus7000 => { nxos51 => 1 }
        },
        juniper => {
            mmx => { junos95 => 1 },
            srx => { junos95 => 1 },
            t => { junos95 => 1 }
        },
        paloalto => {
            pa3000 => { panos803 => 1 },
            pa5000 => { panos803 => 1 }
        }
    };

    if (!defined $configs->{$args->{make}->{value}}) {
        $method->set_error("Network device make '$args->{make}->{value}' isn't supported.");
        return;
    }
    if (!defined $configs->{$args->{make}->{value}}->{$args->{model}->{value}}) {
        $method->set_error("Network device model '$args->{model}->{value}' isn't supported.");
        return;
    }
    if (!defined $configs->{$args->{make}->{value}}->{$args->{model}->{value}}->{$args->{version}->{value}}) {
        $method->set_error("Network device version '$args->{version}->{value}' isn't supported.");
        return;
    }

    my $t;
    eval {
        $t = Template->new(
            INCLUDE_PATH => OESS::Database::SHARE_DIR . "share/customer-templates/:./share/customer-templates/",
            RELATIVE => 1
        );
    };
    if ($@) {
        $method->set_error("Unable to generate configuration: $@");
        return;
    }

    my $ep = new OESS::Endpoint(db => $db, vrf_endpoint_id => $args->{vrf_ep_id}->{value});
    $ep->load_peers;
    my $vars = $ep->to_hash;
    warn Dumper($vars);

    my $config;
    my $ok = $t->process(
        "$args->{make}->{value}/$args->{model}->{value}/$args->{version}->{value}/template.txt",
        $vars,
        \$config
    );
    if (!$ok) {
        $method->set_error("Unable to generate configuration: " . $t->error);
        return;
    }

    return { results => [$config] };
}

$ws->handle_request;
