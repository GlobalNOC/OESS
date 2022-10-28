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
use OESS::DB::Endpoint;

# PURPOSE:
#
# Verify correct response from find_available_unit for QinQ tagged
# Endpoints.
#
# How do we handle the case where VLAN 3 exists and someone requests
# QinQ (3,3)? Ignoring for now.

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
   config => "$path/../conf/database.xml"
);

# my $interfaces = [
#     {
#         'inner_tag' => undef,
#         'interface_id' => '391',
#         'vrf_id' => '2',
#         'state' => 'active',
#         'bandwidth' => '1000',
#         'unit' => '3',
#         'vrf_ep_id' => '2',
#         'tag' => '3',
#         'mtu' => '9000'
#     },
#     {
#         'inner_tag' => '3',
#         'interface_id' => '1',
#         'vrf_id' => '3',
#         'state' => 'active',
#         'bandwidth' => '50',
#         'unit' => '5001',
#         'vrf_ep_id' => '3',
#         'tag' => '3',
#         'mtu' => '9000'
#     }
# ];

# Modify database state to make testing of L2 unit selection possible.
$db->execute_query('update circuit_edge_interface_membership set inner_tag=10, unit=5002 where circuit_edge_id=1971');

# When sTag,cTag tuple directly overlap an existing QinQ but overlap
# is on provided vrf or circuit endpoint id: Accept
#
# Used:     sTag=3 cTag=3
# Conflict: sTag=3 cTag=3

my $unit0 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 1,
    tag => 3,
    inner_tag => 3,
    vrf_ep_id => 3
);
ok($unit0 == 5001, 'Correct Unit for specified L3 Connection returned.');

my $unit1 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 4013,
    inner_tag => 10,
    circuit_ep_id => 1971
);
ok($unit1 == 5002, 'Correct Unit for specified L2 Connection returned.');

# When sTag,cTag tuple directly overlap an existing QinQ and is not on
# provided vrf or circuit endpoint id: Reject
#
# Used:     sTag=3 cTag=3
# Conflict: sTag=3 cTag=3

my $unit11 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 1,
    tag => 3,
    inner_tag => 3,
    vrf_ep_id => 1971
);
ok(!defined $unit11, 'Correct Unit for specified L3 Connection returned.');

my $unit10 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 4013,
    inner_tag => 10,
    circuit_ep_id => 3
);
ok(!defined $unit10, 'Correct Unit for specified L2 Connection returned.');


# When sTag,cTag tuple directly overlap an existing QinQ: Reject
#
# Used:     sTag=3 cTag=3
# Conflict: sTag=3 cTag=3

my $unit2 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 1,
    tag => 3,
    inner_tag => 3
);
ok(!defined $unit2, 'No Unit returned for QinQ already in use on L3 Connection.');

my $unit3 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 4013,
    inner_tag => 10
);
ok(!defined $unit3, 'No Unit returned for QinQ already in use on L2 Connection.');


# When sTag,cTag tuple overlap an existing QinQ sTag but not cTag: Allow
#
# Used: sTag=3 cTag=3
# OK:   sTag=3 cTag=4

my $unit5 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 1,
    tag => 3,
    inner_tag => 4
);
ok($unit5 == 5000, 'Unit returned for available QinQ.');

my $unit9 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 4013,
    inner_tag => 4
);
ok($unit9 == 5000, 'Unit returned for available QinQ.');


# When a QinQ tag is in use, any traditional VLAN the same as the
# QinQ's sTag should be rejected.
#
# Used:    sTag=200 cTag=*
# Conflict VLAN=200

my $unit7 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 4013,
);
ok(!defined $unit7, 'No Unit returned as sTag=4013,cTag=10 already in use on L2 Connection.');
die "Unit $unit7 incorrectly stated as available." if defined $unit7;

my $unit6 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 1,
    tag => 3,
);
ok(!defined $unit6, 'No Unit returned as sTag=3,cTag=3 already in use on L3 Connection.');


# When a traditional VLAN is in use, any QinQ using that same sTag
# should be rejected.
#
# Used:     VLAN=200
# Conflict: sTag=200 cTag=*

my $unit8 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 200,
    inner_tag => 32
);
ok(!defined $unit8, 'No Unit returned as sTag=200,cTag=NULL already in use on L2 Connection.');
die "Unit $unit8 incorrectly stated as available." if defined $unit8;

my $unit4 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 3,
    inner_tag => 4
);
ok(!defined $unit4, 'No Unit returned as sTag=3,cTag=NULL already in use on L3 Connection.');


# When both sTag and cTag overlap nothing in use: Accept
#
# Used: VLAN=200
# OK:   sTag=30 cTag=30

my $unit12 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 30,
    inner_tag => 30
);
ok($unit12 == 5000, 'Unit returned for available QinQ (no overlapping qinq).');


# When both sTag and cTag overlap decom'd vrf: Accept
#
# Decomd: sTag=20 cTag=21
# OK:     sTag=20 cTag=21

my $unit13 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 20,
    inner_tag => 21
);
ok($unit13 == 5000, 'Unit returned for available QinQ (overlapping decomd qinq).');


# When both sTag and cTag overlap active vrf: Reject
#
# Used:     sTag=3 cTag=3
# Conflict: sTag=3 cTag=3

my $unit15 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 4013,
    inner_tag => 10
);
ok(!defined $unit15, 'No Unit returned as sTag=4013,cTag=10 already in use on L2 Connection.');

my $unit14 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 1,
    tag => 3,
    inner_tag => 3
);
ok(!defined $unit14, 'No Unit returned as sTag=3,cTag=3 already in use on L3 Connection.');


# Modify database state to make next available unit 5003 on interface 391.
# A state of 'active' or 'in-review' is enough to reserve the unit
my $to_decom = $db->execute_query(
    "insert into circuit_edge_interface_membership (interface_id,circuit_id,end_epoch,start_epoch,extern_vlan_id,inner_tag,unit,bandwidth,mtu,state)
     values (391,1861,-1,1,20,22,5000,50,9000,'in-review')"
);
warn $to_decom;
$db->execute_query(
    "insert into vrf_ep (interface_id,vrf_id,state,tag,inner_tag,unit,bandwidth,mtu)
     values (391,2,'active',20,23,5001,50,9000)"
);

my $unit16 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 20,
    inner_tag => 24
);
ok($unit16 == 5003, 'Unit returned for available QinQ with in-order unit.');


# Modify database state to decom lowest available qinq unit. Verify is
# first returned unit for next qinq vlan lookup.
$db->execute_query("update circuit_edge_interface_membership set end_epoch=2 where circuit_edge_id=?", [$to_decom]);

my $unit17 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 20,
    inner_tag => 25
);
ok($unit17 == 5000, 'Unit returned for available QinQ with in-order unit after decomd endpoint.');
