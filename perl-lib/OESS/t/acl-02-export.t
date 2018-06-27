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

sub acl_row {
    return {
        eval_position => $_[0],
        workgroup_id  => $_[1],
        allow_deny    => $_[2],
        start         => $_[3],
        end           => $_[4],
    };
}



my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );
my $acl = OESS::ACL->new( interface_id => 45811, db => $db );

ok(defined($db) && defined($acl), 'Sanity-check: can instantiate OESS::Database and OESS::ACL objects');

cmp_deeply(
    $acl->to_hash(),
    {
        interface_id => 45811,
        acls => [
            acl_row(10, 21,  'allow', 100, undef),
            acl_row(20, 31,  'allow', 101, undef),
            acl_row(30, 101, 'allow', 102, undef),
            acl_row(40, 61,  'allow', 103, undef),
            acl_row(50, 71,  'allow', 104, undef),
            acl_row(60, 81,  'allow', 105, undef),
        ],
    },
    'ACL object 1 (id=45811): to_hash returns the right information, in the right order'
);



$acl = OESS::ACL->new( interface_id => 45901, db => $db );

cmp_deeply(
    $acl->to_hash(),
    {
        interface_id => 45901,
        acls => [
            acl_row(10, 21, 'deny',  101, 200 ),
            acl_row(20, 21, 'allow', 120, 125 ),
            acl_row(30, 21, 'allow', -1,  4095),
        ],
    },
    'ACL object 2 (id=45901): to_hash returns the right information, in the right order'
);



$acl = OESS::ACL->new( interface_id => 32291, db => $db );

cmp_deeply(
    $acl->to_hash(),
    {
        interface_id => 32291,
        acls => [
        ],
    },
    'ACL object 3 (id=32291): to_hash returns the right information (namely, no ACLs - none in DB)'
);



$acl = OESS::ACL->new( interface_id => 15, db => $db );

cmp_deeply(
    $acl->to_hash(),
    {
        interface_id => 15,
        acls => [
        ],
    },
    'ACL object 3 (id=15): to_hash returns the right information (namely, no ACLs - interface does not exist)'
);



$acl = OESS::ACL->new( interface_id => undef, db => $db );

cmp_deeply(
    $acl->to_hash(),
    {
        interface_id => undef,
        acls => [
        ],
    },
    'ACL object 3 (id=undef): to_hash returns the right information (namely, no ACLs - no interface_id)'
);
