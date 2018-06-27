#!/usr/bin/perl -T

use strict;

use FindBin;
my $path;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
        $path = $1;
    }
}

use lib "$path";
use OESS::Database;
use OESS::ACL;
use OESSDatabaseTester;

use Test::More tests => 31;
use Test::Deep;
use Data::Dumper;

sub va_test {
    my $result = shift;
    my $expected = shift;
    my $n = shift;
    my $description = shift;

    ok(defined($result), "query $n: vlan_allowed didn't return undef");
    ok(!($result xor $expected), "query $n: $description");
}



my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );
my $acl = OESS::ACL->new( interface_id => 45901, db => $db );

ok(defined($db) && defined($acl), 'Sanity-check: can instantiate OESS::Database and OESS::ACL objects');

va_test(
  $acl->vlan_allowed( workgroup_id => 21, vlan => 150 ),
  0,
  1, 'deny rule before allow rule takes precedence, even if allow rule is wider match'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 21, vlan => 123 ),
  0,
  2, 'deny rule before allow rule takes precedence, even if allow rule is narrower match'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 21, vlan => 1000 ),
  1,
  3, 'rule evaluation falls through non-matching rules until a matching rule is found'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 21, vlan => 100 ),
  1,
  4, 'start and end of ranges are inclusive (part 1: 100)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 21, vlan => 101 ),
  0,
  5, 'start and end of ranges are inclusive (part 2: 101)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 21, vlan => 102 ),
  0,
  6, 'start and end of ranges are inclusive (part 3: 102)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 21, vlan => 199 ),
  0,
  7, 'start and end of ranges are inclusive (part 4: 199)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 21, vlan => 200 ),
  0,
  8, 'start and end of ranges are inclusive (part 5: 200)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 21, vlan => 201 ),
  1,
  9, 'start and end of ranges are inclusive (part 6: 201)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 31, vlan => 300 ),
  0,
  10, 'when workgroup is not listed in ACLs for interface, default is to deny'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 21, vlan => -1 ),
  1,
  11, 'VLAN tag of -1 in range works'
);



$acl = OESS::ACL->new( interface_id => 45811, db => $db );

va_test(
  $acl->vlan_allowed( workgroup_id => 101, vlan => 999 ),
  0,
  12, 'when a workgroup is listed in ACLs for interface, but no ACLs for the workgroup match the tag, deny'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 31, vlan => 100 ),
  0,
  13, 'single-tag bounds work (part 1: 100)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 31, vlan => 101 ),
  1,
  14, 'single-tag bounds work (part 2: 101)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 31, vlan => 102 ),
  0,
  15, 'single-tag bounds work as expected (part 3: 102)'
);
