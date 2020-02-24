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
use Test::More tests => 6;

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

my $unit4 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tage => 3,
    inner_tag => 4
);
ok($unit4 == 5000, 'Unit returned for available QinQ.');

my $unit4 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 1,
    tage => 3,
    inner_tag => 4
);
ok($unit4 == 5000, 'Unit returned for available QinQ.');
