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
use Test::More tests => 20;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::Node;

# Purpose:
#
# Verify interface updates are correctly saved into the database.


OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
   config => "$path/../conf/database.xml"
);


my $model = {
    node_id                => 1,
    name                   => 'host.examle.com', # Optional
    latitude               => 1,                 # Optional
    longitude              => 1,                 # Optional
    operational_state_mpls => 'up',              # Optional
    vlan_tag_range         => '1-4095',          # Optional
    pending_diff           => 1,                 # Optional
    short_name             => 'host',            # Optional
    admin_state            => 'active',          # Optional
    vendor                 => 'juniper',         # Optional
    model                  => 'mx',              # Optional
    sw_version             => '13.3R3',          # Optional
    mgmt_addr              => '192.168.1.1',     # Optional
    loopback_address       => '10.0.0.1',        # Optional
    tcp_port               => 830                # Optional
};


my $i1 = $db->execute_query("select * from node_instantiation where node_id=1");
my $icount1 = @$i1;

my $err = OESS::DB::Node::update(
    db => $db,
    node => $model
);
ok(!defined $err, 'Node updated');
warn $err if defined $err;

# Verify created instantiation entry
my $i2 = $db->execute_query("select * from node_instantiation where node_id=1");
my $icount2 = @$i2;
ok($icount2 == $icount1+1, "Got expected number of instantiation entries.");

# Verify non-effective edit creates no new instantiation entries
OESS::DB::Node::update(
    db => $db,
    node => $model
);
my $i3 = $db->execute_query("select * from node_instantiation where node_id=1");
my $icount3 = @$i2;
ok($icount3 == $icount1+1, "Got expected number of instantiation entries.");

my $intf = OESS::DB::Node::fetch(
    db => $db,
    node_id => 1
);

foreach my $key (keys %$model) {
    ok($intf->{$key} eq $model->{$key}, "got expected $key from db");
}


my $err1 = OESS::DB::Node::update(
    db => $db,
    node => undef
);
ok(defined $err1, "Got expected error $err1");


delete $model->{node_id};
my $err2 = OESS::DB::Node::update(
    db => $db,
    node => $model
);
ok(defined $err2, "Got expected error $err2");
