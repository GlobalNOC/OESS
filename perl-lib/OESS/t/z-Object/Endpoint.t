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
use Test::More tests => 16;

use OESSDatabaseTester;

use OESS::DB;
use OESS::Endpoint;
use OESS::Peer;

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);


my $db = new OESS::DB(
    config  => "$path/../conf/database.xml"
);

my $raw = {
    'bandwidth' => '0',
    'tag' => '1005',
    'peers' => [
        {'asn' => '7','key' => '','local_ip' => '192.168.2.2/24','peer_ip' => '192.168.2.1/24','version' => 4}
    ],
    'cloud_account_id' => '',
    'workgroup_id'   => 1,
    'entity' => 'Indiana University'
};

# In some cases an Endpoint may be created with incomplete peering
# information. In these cases we should auto-generate the missing
# data; For this reason we do not auto-generate Peer objects inside
# the Endpoint object constructor. Validate that when creating an
# Endpoint using a model with pre-defined peers we do not auto-load
# them into Peer objects.

my $ep = new OESS::Endpoint(db => $db, model => $raw);
ok(@{$ep->peers} == 0, 'Peers from raw model not auto-parsed into object.');

my $peer_count = @{$raw->{peers}};
foreach my $raw_peer (@{$raw->{peers}}) {
    my $peer = new OESS::Peer(db => $db, model => $raw_peer);
    $ep->add_peer($peer);
}
ok(@{$ep->peers} == $peer_count, "$peer_count Peer(s) added to Endpoint from raw model after manual creation.");

# =============================
# === move_circuit_endpoint ===
# =============================

my $ep2 = new OESS::Endpoint(db => $db, circuit_id => 4181, interface_id => 391, type => 'circuit');

OESS::Endpoint::move_endpoints(
    db => $db,
    orig_interface_id => 391,
    new_interface_id  => 1
);

my $ep3 = new OESS::Endpoint(db => $db, circuit_id => 4181, interface_id => 1, type => 'circuit');

ok($ep2->interface_id == 391, 'Initial InterfaceID as correctly');
ok($ep3->interface_id == 1, 'InterfaceID updated correctly');

ok($ep2->node_id == 11, 'Initial NodeID as correctly');
ok($ep3->node_id == 1, 'NodeID updated correctly');

ok($ep2->mtu == $ep3->mtu, 'MTU transfered');
ok($ep2->bandwidth == $ep3->bandwidth, 'Bandwidth transfered');
ok($ep2->circuit_ep_id == $ep3->circuit_ep_id, 'CircuitEndpointID transfered');

# =============================
# === move_vrf_endpoint =======
# =============================

my $ep4 = new OESS::Endpoint(db => $db, vrf_endpoint_id => 3, type => 'vrf');

OESS::Endpoint::move_endpoints(
    db => $db,
    orig_interface_id => 1,
    new_interface_id  => 391
);

my $ep5 = new OESS::Endpoint(db => $db, vrf_endpoint_id => 3, type => 'vrf');

ok($ep4->interface_id == 1, 'InterfaceID updated correctly');
ok($ep5->interface_id == 391, 'Initial InterfaceID as correctly');

ok($ep4->node_id == 1, 'NodeID updated correctly');
ok($ep5->node_id == 11, 'Initial NodeID as correctly');

ok($ep4->mtu == $ep5->mtu, 'MTU transfered');
ok($ep4->bandwidth == $ep5->bandwidth, 'Bandwidth transfered');
ok($ep4->vrf_endpoint_id == $ep5->vrf_endpoint_id, 'VRFEndpointID transfered');
