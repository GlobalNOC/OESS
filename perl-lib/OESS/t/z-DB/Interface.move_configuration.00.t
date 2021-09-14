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
use Test::More tests => 18;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::Interface;

# Purpose:
#
# Verify interface details  are correctly moved between interfaces.

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
   config => "$path/../conf/database.xml"
);


my $description = "cool description";
my $vlan_tag_range = "1000-2000";
my $mpls_vlan_tag_range = undef;
my $cloud_interconnect_type = "aws-hosted-connection";
my $cloud_interconnect_id = "placeholder";
my $role = "customer";
my $workgroup_id = 1;

$db->execute_query(
    "update interface set description=?,vlan_tag_range=?,cloud_interconnect_type=?,cloud_interconnect_id=?,workgroup_id=?,role=? where interface_id=45901",
    [
        $description,
        $vlan_tag_range,
        $cloud_interconnect_type,
        $cloud_interconnect_id,
        $workgroup_id,
        $role
    ]
);


my $err;

$err = OESS::DB::Interface::move_configuration(
    db => $db,
    src_interface_id => 45901,
    dst_interface_id => 22
);
ok(defined $err, "Config not moved to non-existing interface.");

$err = OESS::DB::Interface::move_configuration(
    db => $db,
    src_interface_id => 45901,
    dst_interface_id => 45891
);
ok(!defined $err, "Config moved.");

my $src_intf = OESS::DB::Interface::fetch(
    db => $db,
    interface_id => 45901
);

ok(defined $src_intf, "Got source interface.");
# TODO verify config removed
ok(!defined $src_intf->{cloud_interconnect_id}, "Got expected cloud_interconnect_id.");
ok(!defined $src_intf->{cloud_interconnect_type}, "Got expected cloud_interconnect_type.");
ok($src_intf->{description} eq $src_intf->{name}, "Got expected description.");
ok($src_intf->{role} eq "unknown", "Got expected role.");
ok($src_intf->{vlan_tag_range} eq "1-4095", "Got expected vlan_tag_range.");
ok(!defined $src_intf->{mpls_vlan_tag_range}, "Got expected mpls_vlan_tag_range.");
ok(!defined $src_intf->{workgroup_id}, "Got expected workgroup_id.");

my $dst_intf = OESS::DB::Interface::fetch(
    db => $db,
    interface_id => 45891
);
# warn Dumper($dst_intf);
ok(defined $dst_intf, "Got destination interface.");
# TODO verify config moved
ok($dst_intf->{cloud_interconnect_id} eq $cloud_interconnect_id, "Got expected cloud_interconnect_id.");
ok($dst_intf->{cloud_interconnect_type} eq $cloud_interconnect_type, "Got expected cloud_interconnect_type.");
ok($dst_intf->{description} eq $description, "Got expected description.");
ok($dst_intf->{role} eq $role, "Got expected role.");
ok($dst_intf->{vlan_tag_range} eq $vlan_tag_range, "Got expected vlan_tag_range.");
ok($dst_intf->{mpls_vlan_tag_range} eq $mpls_vlan_tag_range, "Got expected mpls_vlan_tag_range.");
ok($dst_intf->{workgroup_id} eq $workgroup_id, "Got expected workgroup_id.");
