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
use Test::More tests => 83;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::Node;

# Purpose:
#
# Verify node fetches pull correct information from database for case when you
# have the node_name only and when you have node_id


OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
   config => "$path/../conf/database.xml"
);

my $node = OESS::DB::Node::fetch(
    db =>$db,
    node_id => 1
);

warn "Error during fetch with node_id"  if !defined $node;

my $model = {
    node_id => 1,
    name => 'Node 1',
    longitude => -121.987513,
    latitude => 37.373779,
    operational_state => 'up',
    network_id => 1,
    vlan_tag_range => '100-4094',
    default_forward => '1',
    default_drop => '0',
    max_flows => 4000,
    tx_delay_ms => 0,
    send_barrier_bulk => 1,
    max_static_mac_flows => 4000,
    in_maint => 'no',
    pending_diff => 0,
    operational_state_mpls => 'unknown',
    short_name => undef,
    end_epoch => -1,
    start_epoch => 1348237415,
    admin_state => 'active',
    dpid => '155568807680',
    openflow => 1,
    mpls => 1,
    vendor => undef,
    model => undef,
    sw_version => undef,
    mgmt_addr => undef,
    loopback_address => undef,
    tcp_port => 830
};

foreach my $key (keys %$model) {
    if (defined $model->{$key}) {
       ok($node->{$key} eq $model->{$key}, "got expected $key from db");
    } else {
       ok(!defined $node->{$key}, "got expected $key from db");
    }
}

$node = OESS::DB::Node::fetch(
    db => $db,
    name => 'Node 1'
);

warn "Error during fetch with node_name" if !defined $node;

foreach my $key (keys %$model) {
    if (defined $model->{$key}) {
       ok($node->{$key} eq $model->{$key}, "got expected $key from db");
    } else {
       ok(!defined $node->{$key}, "got expected $key from db");
    }
}


# create node
my ($new_node_id, $new_node_err) = OESS::DB::Node::create(
    db    => $db,
    model => {
        name       => 'demo-switch.example.com',
        latitude   => 1.01,
        longitude  => 1.01,
        ip_address => '192.168.1.1',
        make       => 'Juniper',
        model      => 'MX',
        controller => 'netconf'
    }
);
ok($new_node_id == 5736, "Node $new_node_id created.");
ok(!defined $new_node_err, "No error generated during node creation.");
warn $new_node_err if defined $new_node_err;


# edit node
my $update_node_err = OESS::DB::Node::update(
    db   => $db,
    node => {
        node_id    => $new_node_id,
        name       => 'demo-switch2.example.com',
        latitude   => 2,
        longitude  => 2,
        sw_version => '123',
        controller => 'nso',
        mgmt_addr  => '192.168.1.2'
    }
);
ok(!defined $update_node_err, "No error generated during node update.");
warn $update_node_err if defined $update_node_err;

$node = OESS::DB::Node::fetch(
    db      => $db,
    node_id => $new_node_id
);
ok($node->{name} eq 'demo-switch2.example.com', "Node name is $node->{name}.");
ok($node->{latitude} == 2, "Node latitude is $node->{latitude}.");
ok($node->{longitude} == 2, "Node longitude is $node->{longitude}.");
ok($node->{sw_version} eq '123', "Node sw_version is $node->{sw_version}.");
ok($node->{controller} eq 'nso', "Node controller is $node->{controller}.");
ok($node->{dpid} eq '3232235777', "Node dpid is $node->{dpid}.");
ok($node->{admin_state} eq 'active', "Node admin_state is $node->{admin_state}.");
ok($node->{mgmt_addr} eq '192.168.1.2', "Node ip_address is $node->{mgmt_addr}.");


# Verify two instantiation table entries for node
my $res = $db->execute_query("select * from node_instantiation where node_id=?", [$new_node_id]);
ok(@$res == 2, "Got expected number of node_instantiations entries.");


# Must be 1 second between all node updates
sleep 1;


# decom node
my $decom_node_err = OESS::DB::Node::decom(
    db      => $db,
    node_id => $new_node_id
);
ok(!defined $decom_node_err, "No error generated during node decom.");
warn $decom_node_err if defined $decom_node_err;

$node = OESS::DB::Node::fetch(
    db      => $db,
    node_id => $new_node_id
);
ok($node->{name} eq 'demo-switch2.example.com', "Node name is $node->{name}.");
ok($node->{latitude} == 2, "Node latitude is $node->{latitude}.");
ok($node->{longitude} == 2, "Node longitude is $node->{longitude}.");
ok($node->{sw_version} eq '123', "Node sw_version is $node->{sw_version}.");
ok($node->{controller} eq 'nso', "Node controller is $node->{controller}.");
ok($node->{dpid} eq '3232235777', "Node dpid is $node->{dpid}.");
ok($node->{admin_state} eq 'decom', "Node admin_state is $node->{admin_state}.");
ok($node->{mgmt_addr} eq '192.168.1.2', "Node ip_address is $node->{mgmt_addr}.");


# Verify three instantiation table entries for node
my $res2 = $db->execute_query("select * from node_instantiation where node_id=?", [$new_node_id]);
ok(@$res2 == 3, "Got expected number of node_instantiations entries.");

# Delete node
my $del_err = OESS::DB::Node::delete(
    db      => $db,
    node_id => $new_node_id
);
ok(!defined $del_err, "No error generated during node delete.");
warn $del_err if defined $del_err;

# Verify zero entries for node
my $res3 = $db->execute_query("select * from node where node_id=?", [$new_node_id]);
ok(@$res3 == 0, "Got expected number of node entries.");

# Verify zero instantiation table entries for node
my $res4 = $db->execute_query("select * from node_instantiation where node_id=?", [$new_node_id]);
ok(@$res4 == 0, "Got expected number of node_instantiations entries.");
