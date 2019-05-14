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
    name            => 'circuit_id',
    pattern         => $GRNOC::WebService::Regex::INTEGER,
    required        => 0,
    description     => "-1 or undefined indicate circuit is to be added."
);
$provision->add_input_parameter(
    name => 'workgroup_id',
    pattern => $GRNOC::WebService::Regex::INTEGER,
    required => 1,
    description => 'Identifier of managing Workgroup.'
);

$provision->add_input_parameter(
    name            => 'description',
    pattern         => $GRNOC::WebService::Regex::TEXT,
    required        => 1,
    description     => "The description of the circuit."
);

$provision->add_input_parameter(
	name            => 'provision_time',
	pattern         => $GRNOC::WebService::Regex::INTEGER,
	required        => 1,
	description     => "Timestamp of when circuit should be created in epoch time format. -1 means now."
);
$provision->add_input_parameter(
    name            => 'remove_time',
    pattern         => $GRNOC::WebService::Regex::INTEGER,
    required        => 1,
    description     => "The time the circuit should be removed from the network in epoch time format. -1 means never."
);

$provision->add_input_parameter(
	name            => 'link',
	pattern         => $GRNOC::WebService::Regex::TEXT,
	required        => 0,
	multiple        => 1,
	description     => "Array of names of links to be used in the primary path."
);

$provision->add_input_parameter(
    name            => 'endpoints',
    pattern         => $GRNOC::WebService::Regex::TEXT,
    required        => 1,
    multiple        => 0,
    description     => 'JSON array of endpoints to be used.'
);

$provision->add_input_parameter(
    name            => 'external_identifier',
    pattern         => $GRNOC::WebService::Regex::TEXT,
    required        => 0,
    description     => "External Identifier of the circuit"
);
$provision->add_input_parameter(
    name            => 'remote_url',
    pattern         => $GRNOC::WebService::Regex::TEXT,
    required        => 0,
    description     => "The remote URL for the IDC"
);
$provision->add_input_parameter(
    name            => 'remote_requester',
    pattern         => $GRNOC::WebService::Regex::TEXT,
    required        => 0,
    description     => "The remote requester."
);
$ws->register_method($provision);

sub provision {
    my ($method, $args) = @_;

    my $user = OESS::DB::User::get(db => $db, auth_name => $ENV{REMOTE_USER});
    if ($user->{type} eq 'read-only') {
        $method->set_error("User '$user->{auth_name}' is read-only.");
        return;
    }

    my $circuit = new OESS::L2Circuit(
        db => $db,
        model => {
            name => $args->{description}->{value},
            description => $args->{description}->{value},
            remote_url => $args->{remote_url}->{value},
            remote_requester => $args->{remote_requester}->{value},
            external_identifier => $args->{external_identifier}->{value},
            provision_time => $args->{provision_time}->{value},
            remove_time => $args->{remove_time}->{value},
            user_id => $user->{user_id},
            workgroup_id => $args->{workgroup_id}->{value}
        }
    );

    # Endpoint: { entity: 'entity name', bandwidth: 0, tag: 100, inner_tag: 100, peerings: [{ version: 4 }]  }
    foreach my $value (@{$args->{endpoint}->{value}}) {
        my $endpoint;
        eval{
            $endpoint = decode_json($value);
        };
        if ($@) {
            $method->set_error("Cannot decode endpoint: $@");
            return;
        }

        my $entity = new OESS::Entity(db => $db, name => $endpoint->{entity});
        my $interface = $entity->select_interface(
            inner_tag => $endpoint->{inner_tag},
            tag => $endpoint->{tag},
            workgroup_id => $args->{workgroup_id}->{value}
        );
        if (!defined $interface) {
            $method->set_error("Cannot find a valid Interface for $endpoint->{entity}.");
            return;
        }

        $endpoint->{interface} = $interface->name;
        $endpoint->{node} = $interface->node;
        my $endpoint = new OESS::Endpoint(db => $db, model => $endpoint);

        if ($interface->cloud_interconnect_type eq 'azure-express-route') {
            my $interface2 = $entity->select_interface(
                inner_tag => $endpoint->{inner_tag},
                tag => $endpoint->{tag},
                workgroup_id => $args->{workgroup_id}->{value}
            );
            if (!defined $interface2) {
                $method->set_error("Cannot find a valid Interface for $endpoint->{entity}.");
                return;
            }

            $endpoint->{interface} = $interface2->name;
            $endpoint->{node} = $interface2->node;
            my $endpoint2 = new OESS::Endpoint(db => $db, model => $ep);

            if ($endpoint->cloud_interconnect_id =~ /PRI/) {
                $endpoint->add_peer(new OESS::Peer(
                    db => $db,
                    asn => 12076,
                    key => '',
                    local_ip => '192.168.100.249/30',
                    peer_ip  => '192.168.100.250/30',
                    version  => 4
                ));
                $endpoint2->add_peer(new OESS::Peer(
                    db => $db,
                    asn => 12076,
                    key => '',
                    local_ip => '192.168.100.253/30',
                    peer_ip  => '192.168.100.254/30',
                    version  => 4
                ));
            } else {
                $endpoint2->add_peer(new OESS::Peer(
                    db => $db,
                    asn => 12076,
                    key => '',
                    local_ip => '192.168.100.249/30',
                    peer_ip  => '192.168.100.250/30',
                    version  => 4
                ));
                $endpoint->add_peer(new OESS::Peer(
                    db => $db,
                    asn => 12076,
                    key => '',
                    local_ip => '192.168.100.253/30',
                    peer_ip  => '192.168.100.254/30',
                    version  => 4
                ));
            }
        } else {
            # TODO setup peering without azure weirdness
        }

        warn 'interface: ' . Dumper($interface);


        # $circuit->add_endpoint();
    }

    warn Dumper($circuit->to_hash);

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

    my $user = OESS::DB::User::get(db => $db, auth_name => $ENV{REMOTE_USER});
    if ($user->{type} eq 'read-only') {
        $method->set_error("User '$user->{auth_name}' is read-only.");
        return;
    }

    return {status => 1};
}


$ws->handle_request();
