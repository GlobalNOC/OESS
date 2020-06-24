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
use Test::More tests => 13;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::Interface;

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
    interface_id => 41,
    name => 'e33/1',
    description => 'e33/1',
    operational_state => 'down',
    role => 'unknown',
    vlan_tag_range => '2-10',
    workgroup_id => 11,
    mpls_vlan_tag_range => '11-21',
    cloud_interconnect_type => 'aws-hosted-connection',
    cloud_interconnect_id => 'dxcon_123456'
};

my $err = OESS::DB::Interface::update(
    db => $db,
    interface => $model
);
ok(!defined $err, 'Interface updated');
warn $err if defined $err;


my $intf = OESS::DB::Interface::fetch(
    db => $db,
    interface_id => 41
);

foreach my $key (keys %$model) {
    ok($intf->{$key} eq $model->{$key}, "got expected $key from db");
}


my $err1 = OESS::DB::Interface::update(
    db => $db,
    interface => undef
);
ok(defined $err1, "Got expected error $err1");


delete $model->{interface_id};
my $err2 = OESS::DB::Interface::update(
    db => $db,
    interface => $model
);
ok(defined $err2, "Got expected error $err2");
