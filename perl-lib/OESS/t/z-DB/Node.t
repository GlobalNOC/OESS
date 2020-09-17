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
use Test::More tests => 58;

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


