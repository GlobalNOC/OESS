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

use Test::More tests => 6;
use Test::Deep;
use Data::Dumper;

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );
ok(defined($db), 'Can instantiate OESS::Database object');

my $acl = OESS::ACL->new( interface_id => 45811, db => $db );
ok(defined($acl), 'Can instantiate an OESS::ACL for an interface that\'s present');

$acl = OESS::ACL->new( interface_id => 15, db => $db );
ok(defined($acl), 'Can instantiate an OESS::ACL for an interface that\'s *not* present');

$acl = OESS::ACL->new( interface_id => undef, db => $db );
ok(defined($acl), 'Can instantiate an OESS::ACL for undefined interface');

$acl = OESS::ACL->new( db => undef, interface_id => 45811 );
ok(!defined($acl), 'OESS::ACL::new should return undef if not given a DB object (1)');

$acl = OESS::ACL->new( interface_id => 45811 );
ok(!defined($acl), 'OESS::ACL::new should return undef if not given a DB object (2)');
