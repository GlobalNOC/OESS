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
use Test::More tests => 5;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::Endpoint;

# PURPOSE:
#
# Verify correct response from find_available_unit for basic
# VLANs. See Endpoint.find_available_unit.01.t for QinQ related tests.

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

my $unit0 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 3,
    vrf_ep_id => 2
);
ok($unit0 == 3, 'Correct Unit for specified L3 Connection returned.');

my $unit1 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 4013,
    circuit_ep_id => 1971
);
ok($unit1 == 4013, 'Correct Unit for specified L2 Connection returned.');

my $unit2 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 3
);
ok(!defined $unit2, 'No Unit returned for VLAN already in use on L3 Connection.');

my $unit3 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 4013
);
ok(!defined $unit3, 'No Unit returned for VLAN already in use on L2 Connection.');

my $unit4 = OESS::DB::Endpoint::find_available_unit(
    db => $db,
    interface_id => 391,
    tag => 201
);
ok($unit4 == 201, 'Unit returned for available VLAN.');
