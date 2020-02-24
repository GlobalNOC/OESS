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
use Test::More tests => 3;

use OESSDatabaseTester;

use OESS::DB;
use OESS::VRF;

# PURPOSE:
#
# Verify that calling OESS::VRF->update without loading all child
# objects preserves all child relations. This test was put in place
# after OESS::VRF->update_db (since removed) completely recreated its
# Endpoints (delete followed by an add); This resulted in the Peers
# associated with the Endpoints to be unexpectedly removed from the
# database.

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
   config => "$path/../conf/database.xml"
);

my $vrf = new OESS::VRF(db => $db, vrf_id => 3);
$vrf->name('updated name');
$vrf->update;

my $vrf2 = new OESS::VRF(db => $db, vrf_id => 3);
$vrf2->load_endpoints;

ok($vrf2->name eq 'updated name', 'VRF has expected name.');
ok(@{$vrf2->endpoints} == 1, 'One Endpoint associated with VRF.');
ok($vrf2->endpoints->[0]->{vrf_endpoint_id} == 3, 'Expected Endpoint Id associated with VRF.');
