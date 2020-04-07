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
use Test::More tests => 11;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::ACL;
use OESS::ACL;

# PURPOSE: Verify that calling OESS::ACL->vlan_allowed returns 1 when
# a single VLAN is allowed on an ACL. There are two cases to test.
#
# 1. start is defined and end is undef
# 2. start and end are the same VLAN

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
   config => "$path/../conf/database.xml"
);

my $workgroup_id = 31;
my $interface_acl_id = 4;

my $acld = OESS::DB::ACL::fetch(db => $db, interface_acl_id => $interface_acl_id);
ok(!defined $acld->{end}, 'acl.end is undef in db');
ok($acld->{start} == 101, 'acl.start is defined in db');

my $acl = new OESS::ACL(db => $db, interface_acl_id => $interface_acl_id);
ok($acl->{end} == 101, 'acl.end is defined in obj');
ok($acl->{start} == 101, 'acl.end is defined in obj');
ok($acl->{start} == $acl->{end}, 'acl.start == acl.end after loaded via object');

my $acle = OESS::DB::ACL::update(db => $db, acl => {interface_acl_id => $interface_acl_id, end => 101});
ok(defined $acle, 'acl updated in db');

my $acld1 = OESS::DB::ACL::fetch(db => $db, interface_acl_id => $interface_acl_id);
ok($acld1->{end} == 101, 'acl.end is defined in db');
ok($acld1->{start} == 101, 'acl.start is defined in db');

my $acl1 = new OESS::ACL(db => $db, interface_acl_id => $interface_acl_id);
ok($acl1->{end} == 101, 'acl.end is defined in obj');
ok($acl1->{start} == 101, 'acl.end is defined in obj');
ok($acl1->{start} == $acl1->{end}, 'acl.start == acl.end after loaded via object');
