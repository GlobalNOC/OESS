#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
my $path;

BEGIN {
    if ($FindBin::Bin =~ /(.*)/) {
        $path = $1;
    }
}
use lib "$path/..";


use Data::Dumper;
use Test::More tests => 10;

use OESSDatabaseTester;

use OESS::Config;
use OESS::DB;
use OESS::VRF;

# PURPOSE:
#
# Verify that calling OESS::VRF->update without loading all child
# objects preserves all child relations. This test was put in place
# after OESS::VRF->update_db (since removed) completely recreated its
# Endpoints (delete followed by an add); This resulted in the Peers
# associated with the Endpoints to be unexpectedly removed from the
# database.

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $test_config = new OESS::Config(config_filename => "$path/../conf/database.xml");

my $db = new OESS::DB(
   config => "$path/../conf/database.xml"
);

my $workgroup_id = 31;

my $vrf = new OESS::VRF(
    config => $test_config,
    db     => $db,
    model  => {
        name           => 'Test_4',
        description    => 'Test_4',
        local_asn      =>  1,
        workgroup_id   =>  $workgroup_id,
        provision_time => -1,
        remove_time    => -1,
        created_by_id  => 11,
        last_modified_by_id => 11
    }
);
my ($id, $err) = $vrf->create;
ok(defined $id, "Created vrf $vrf->{vrf_id}.");
ok(!defined $err, "Created vrf $vrf->{vrf_id} without error.");

my $endpoints = [
    {
        bandwidth => 0,
        mtu => 1500,
        tag => 2007,
        peerings => [
            { peer_asn => 7, md5_key => '', local_ip => '192.168.7.2/31', peer_ip => '192.168.7.3/31', version => 4 }
        ],
        entity => 'B University-Metropolis'
    },
    {
        bandwidth => 0,
        mtu => 1500,
        tag => 2008,
        peerings => [
            { peer_asn => 8, md5_key => '', local_ip => '192.168.8.2/31', peer_ip => '192.168.8.3/31', version => 4 }
        ],
        entity => 'Big State TeraPOP'
    }
];

foreach my $ep (@$endpoints) {
    my $entity = new OESS::Entity(db => $db, name => $ep->{entity});
    my ($interface, $interface_err) = $entity->select_interface(
        inner_tag    => $ep->{inner_tag},
        tag          => $ep->{tag},
        workgroup_id => $workgroup_id
    );
    $ep->{type}         = 'vrf';
    $ep->{entity_id}    = $entity->{entity_id};
    $ep->{interface}    = $interface->{name};
    $ep->{interface_id} = $interface->{interface_id};
    $ep->{node}         = $interface->{node}->{name};
    $ep->{node_id}      = $interface->{node}->{node_id};
    $ep->{cloud_interconnect_id}   = $interface->cloud_interconnect_id;
    $ep->{cloud_interconnect_type} = $interface->cloud_interconnect_type;

    my $endpoint = new OESS::Endpoint(db => $db, model => $ep);
    my ($ep_id, $ep_err) = $endpoint->create(
        vrf_id       => $vrf->vrf_id,
        workgroup_id => $workgroup_id
    );
    ok(!defined $ep_err, "Created endpoint $endpoint->{vrf_endpoint_id}.");
    if (defined $ep_err) {
        warn "$ep_err";
    }
    $vrf->add_endpoint($endpoint);

    foreach my $peering (@{$ep->{peerings}}) {
        my $peer = new OESS::Peer(db => $db, model => $peering);
        my ($peer_id, $peer_err) = $peer->create(vrf_ep_id => $endpoint->vrf_endpoint_id);
        ok(!defined $peer_err, "Created peer $peer->{vrf_ep_peer_id}.");
        if (defined $peer_err) {
            warn "$peer_err";
        }
        $endpoint->add_peer($peer);
    }
}

my $loaded_vrf = new OESS::VRF(config => $test_config, db => $db, vrf_id => $vrf->vrf_id);
$loaded_vrf->name('bahahaha');
$loaded_vrf->update;

my $loaded_vrf2 = new OESS::VRF(config => $test_config, db => $db, vrf_id => $vrf->vrf_id);
ok($loaded_vrf2->name eq 'bahahaha', 'VRF name update validated.');

$loaded_vrf2->load_endpoints;
foreach my $ep (@{$loaded_vrf2->endpoints}) {
    $ep->load_peers;
    ok(@{$ep->peers} == 1, "Looked up exactly 1 Peer on Endpoint.");
}

my $ok = $vrf->decom(user_id => 1);
ok($ok, "VRF Decom'd");
