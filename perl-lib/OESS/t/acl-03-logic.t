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
use OESS::DB;
use OESS::ACL;
use OESSDatabaseTester;

use Test::More tests => 53;
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



my $db = OESS::DB->new( config => OESSDatabaseTester::getConfigFilePath() );
my $acl = OESS::ACL->new( interface_id => 45901, db => $db );

ok(defined($db) && defined($acl), 'Sanity-check: can instantiate OESS::DB and OESS::ACL objects');

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
  10, 'when workgroup is not listed in ACLs for interface, default is to deny (not the interface owner)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 1, vlan => 300 ),
  0,
  11, 'when workgroup is not listed in ACLs for interface, default is to deny, even for the owner of the interface'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 21, vlan => -1 ),
  1,
  12, 'VLAN tag of -1 in range works'
);



$acl = OESS::ACL->new( interface_id => 45811, db => $db );

va_test(
  $acl->vlan_allowed( workgroup_id => 101, vlan => 999 ),
  0,
  13, 'when a workgroup is listed in ACLs for interface, but no ACLs for the workgroup match the tag, deny'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 31, vlan => 100 ),
  0,
  14, 'single-tag bounds work (part 1: 100)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 31, vlan => 101 ),
  1,
  15, 'single-tag bounds work (part 2: 101)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 31, vlan => 102 ),
  0,
  16, 'single-tag bounds work as expected (part 3: 102)'
);



$acl = OESS::ACL->new( interface_id => 32291, db => $db );

va_test(
  $acl->vlan_allowed( workgroup_id => 31, vlan => 1729 ),
  0,
  17, 'when no ACLs exist for an interface, deny (not the interface owner)'
);



$acl = OESS::ACL->new( interface_id => 501, db => $db );

va_test(
  $acl->vlan_allowed( workgroup_id => 11, vlan => 1729 ),
  0,
  18, 'when no ACLs exist for an interface, deny, even for the interface owner'
);



$acl = OESS::ACL->new( interface_id => 21, db => $db );

va_test(
  $acl->vlan_allowed( workgroup_id => 11, vlan => 1155 ),
  1,
  19, 'ACLs with null workgroup_id apply to all workgroups (1)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 101, vlan => 1155 ),
  1,
  20, 'ACLs with null workgroup_id apply to all workgroups (2)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 61, vlan => 1130 ),
  1,
  21, 'wildcard workgroup matches are also first-match-wins (1)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 11, vlan => 1150 ),
  0,
  22, 'wildcard workgroup matches are also first-match-wins (2)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 101, vlan => 1150 ),
  0,
  23, 'wildcard workgroup matches are also first-match-wins (3)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 101, vlan => 1163 ),
  1,
  24, 'first-match-wins, even when wildcard workgroup matches follow (1)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 101, vlan => 1174 ),
  0,
  25, 'first-match-wins, even when wildcard workgroup matches follow (2)'
);

va_test(
  $acl->vlan_allowed( workgroup_id => 71, vlan => 3000 ),
  0,
  26, 'even in presence of wildcard workgroup matches, when no ACLs match, deny'
);
