#!/usr/bin/perl -I /home/aragusa/OESS/perl-lib/OESS/lib

use strict;
use warnings;

use Data::Dumper;
use DateTime;
use Digest::MD5 qw(md5_hex);
use JSON;
use Log::Log4perl;

use GRNOC::WebService::Dispatcher;
use GRNOC::WebService::Method;

use OESS::Cloud;
use OESS::Cloud::AWS;
use OESS::DB;
use OESS::DB::Circuit;
use OESS::DB::Entity;
use OESS::DB::User;
use OESS::L2Circuit;
use OESS::RabbitMQ::Client;
use OESS::VRF;


Log::Log4perl::init_and_watch('/etc/oess/logging.conf', 10);


my $db = OESS::DB->new();
my $mq = OESS::RabbitMQ::Client->new(
    topic   => 'OF.FWDCTL.RPC',
    timeout => 120
);

my $ws = GRNOC::WebService::Dispatcher->new();

my $get_circuits = GRNOC::WebService::Method->new(
    name => 'get_circuits',
    callback => \&get_circuits,
    description => 'Returns a list of Circuits filtered by the provided parameters.'
);
$get_circuits->add_input_parameter(
    name => 'workgroup_id',
    pattern => $GRNOC::WebService::Regex::INTEGER,
    required => 1,
    description => 'Identifier of Workgroup to filter results by.'
);
$get_circuits->add_input_parameter(
    name => 'circuit_id',
    pattern => $GRNOC::WebService::Regex::INTEGER,
    required => 0,
    description => 'Identifier of Circuit to filter results by.'
);
$get_circuits->add_input_parameter(
    name => 'state',
    pattern => $GRNOC::WebService::Regex::TEXT,
    default => 'active',
    required => 0,
    description => 'State of Circuits to search for. Must be `active` or `decom`.'
);
$ws->register_method($get_circuits);

sub get_circuits {
    my ($method, $args) = @_;

    my $circuits = [];
    my $circuit_datas = OESS::DB::Circuit::fetch_circuits(
        db => $db,
        state => $args->{state}->{value},
        circuit_id => $args->{circuit_id}->{value},
        workgroup_id => $args->{workgroup_id}->{value}
    );

    foreach my $data (@$circuit_datas) {
        my $first_circuit = OESS::DB::Circuit::fetch_circuits(
            db => $db,
            circuit_id => $data->{circuit_id},
            first => 1
        );

        $data->{created_by_id} = $first_circuit->[0]->{user_id} || $data->{user_id};
        $data->{created_on_epoch} = $first_circuit->[0]->{start_epoch} || $data->{start_epoch};
        $data->{created_on} = DateTime->from_epoch(
            epoch => $data->{'created_on_epoch'}
        )->strftime('%m/%d/%Y %H:%M:%S');

        my $obj = new OESS::L2Circuit(db => $db, model => $data);
        $obj->load_users;
        $obj->load_paths;
        $obj->load_endpoints;

        push @$circuits, $obj->to_hash;
    }

    return {results => $circuits};
}


my $provision = GRNOC::WebService::Method->new(
    name => 'provision',
    callback => \&provision,
    description => 'Creates and provisions a new Circuit.'
);
$provision->add_input_parameter(
    name => 'workgroup_id',
    pattern => $GRNOC::WebService::Regex::INTEGER,
    required => 1,
    description => 'Identifier of managing Workgroup.'
);
$ws->register_method($provision);

sub provision {
    my ($method, $args) = @_;

    my $user = OESS::DB::User::get(db => $db, auth_name => $ENV{REMOTE_USER});
    if ($user->{type} eq 'read-only') {
        $method->set_error("User '$user->{auth_name}' is read-only.");
        return;
    }

    return {status => 1};
}


my $remove = GRNOC::WebService::Method->new(
    name => 'remove',
    callback => \&remove,
    description => 'Removes a Circuit from the network.'
);
$remove->add_input_parameter(
    name => 'workgroup_id',
    pattern => $GRNOC::WebService::Regex::INTEGER,
    required => 1,
    description => 'Identifier of managing Workgroup.'
);
$remove->add_input_parameter(
    name => 'circuit_id',
    pattern => $GRNOC::WebService::Regex::INTEGER,
    required => 1,
    description => 'Identifier of Circuit to remove.'
);
$ws->register_method($remove);

sub remove {
    my ($method, $args) = @_;
    return {status => 1};
}


$ws->handle_request();
