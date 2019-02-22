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

use Test::More tests => 6;
use Test::Exception;

use Test::Deep;
use Data::Dumper;

my $db = OESS::DB->new( config => OESSDatabaseTester::getConfigFilePath() );
ok(defined($db), 'Can instantiate OESS::DB object');

my $acl = OESS::ACL->new( interface_acl_id => 1, db => $db );
ok(defined($acl), 'Can instantiate an OESS::ACL for an interface that\'s present');

$acl = OESS::ACL->new( interface_acl_id => 200, db => $db );
ok(defined($acl), 'Can instantiate an OESS::ACL for an interface that\'s *not* present');

dies_ok { my $acl = OESS::ACL->new(interface_acl_id => undef, db => $db); } 'OESS::ACL::new should die if missing model or interface_acl_id';

dies_ok { my $acl = OESS::ACL->new(db => undef, interface_acl_id => 1); } 'OESS::ACL::new should die if not given a DB object (1)';

dies_ok { my $acl = OESS::ACL->new(interface_acl_id => 1); } 'OESS::ACL::new should die if not given a DB object key (2)';
