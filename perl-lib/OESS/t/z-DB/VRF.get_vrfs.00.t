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
use Test::Deep;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::VRF;

# Purpose:
#
# Verify results of get_vrfs based on filter args

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
    config => "$path/../conf/database.xml"
);

my $exp = [
    { 'vrf_id' => '2' },
    { 'vrf_id' => '4' },
    { 'vrf_id' => '5' },
    { 'vrf_id' => '1' },
];
my $vrfs = OESS::DB::VRF::get_vrfs(
    db => $db,
    workgroup_id => 21
);
cmp_deeply($vrfs, set(@$exp), "Got expected vrfs by workgroup_id.");

$exp = [
    { 'vrf_id' => '2' },
    { 'vrf_id' => '1' },
    { 'vrf_id' => '3' },
];
$vrfs = OESS::DB::VRF::get_vrfs(
    db => $db,
    state => 'active'
);
cmp_deeply($vrfs, set(@$exp), "Got expected vrfs by state.");

$exp = [
    { 'vrf_id' => '2' },
    { 'vrf_id' => '1' },
];
$vrfs = OESS::DB::VRF::get_vrfs(
    db => $db,
    state => 'active',
    workgroup_id => 21
);
cmp_deeply($vrfs, set(@$exp), "Got expected vrfs by state, workgroup_id.");

$exp = [
    { 'vrf_id' => '4' },
    { 'vrf_id' => '5' },
];
$vrfs = OESS::DB::VRF::get_vrfs(
    db => $db,
    state => 'decom',
    workgroup_id => 21
);
cmp_deeply($vrfs, set(@$exp), "Got expected vrfs by state, workgroup_id.");

$exp = [
    { 'vrf_id' => '2' },
];
$vrfs = OESS::DB::VRF::get_vrfs(
    db => $db,
    state => 'active',
    vrf_id => 2,
    workgroup_id => 21
);
cmp_deeply($vrfs, set(@$exp), "Got expected vrfs by state, vrf_id, workgroup_id.");

$exp = [
    { 'vrf_id' => '2' },
];
$vrfs = OESS::DB::VRF::get_vrfs(
    db => $db,
    vrf_id => 2
);
cmp_deeply($vrfs, set(@$exp), "Got expected vrfs by vrf_id.");

$exp = [
    { 'vrf_id' => '3' },
    { 'vrf_id' => '4' },
    { 'vrf_id' => '5' },
];
$vrfs = OESS::DB::VRF::get_vrfs(
    db => $db,
    node_id => 1
);
cmp_deeply($vrfs, set(@$exp), "Got expected vrfs by node_id.");

$exp = [
    { 'vrf_id' => '3' },
];
$vrfs = OESS::DB::VRF::get_vrfs(
    db => $db,
    state => 'active',
    node_id => 1
);
cmp_deeply($vrfs, set(@$exp), "Got expected vrfs by state, node_id.");

$exp = [
    { 'vrf_id' => '2' },
    { 'vrf_id' => '4' },
    { 'vrf_id' => '5' },
];
$vrfs = OESS::DB::VRF::get_vrfs(
    db => $db,
    interface_id => 391
);
cmp_deeply($vrfs, set(@$exp), "Got expected vrfs by interface_id.");

$exp = [
    { 'vrf_id' => '2' },
];
$vrfs = OESS::DB::VRF::get_vrfs(
    db => $db,
    state => 'active',
    interface_id => 391
);
cmp_deeply($vrfs, set(@$exp), "Got expected vrfs by state, interface_id.");
