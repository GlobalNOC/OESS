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

use Test::More tests => 7;
use Test::Deep;
use Data::Dumper;

sub acl_row {
    return {
        eval_position => $_[0],
        workgroup_id  => $_[1],
        allow_deny    => $_[2],
        start         => $_[3],
        end           => $_[4],
        entity_id     => $_[5],
    };
}



my $db = OESS::DB->new( config => OESSDatabaseTester::getConfigFilePath() );
my $acl = OESS::ACL->new( interface_id => 45811, db => $db );

ok(defined($db) && defined($acl), 'Sanity-check: can instantiate OESS::DB and OESS::ACL objects');
warn Dumper($acl->to_hash());
cmp_deeply(
    $acl->to_hash(),
    {
        interface_id => 45811,
        acls => [
            acl_row(10,  21, 'allow', 100, undef, undef),
            acl_row(20,  31, 'allow', 101, undef, undef),
            acl_row(22, 241, 'allow',   1,  4095, undef),
            acl_row(30, 101, 'allow', 102, undef, undef),
            acl_row(40,  61, 'allow', 103, undef, undef),
            acl_row(50,  71, 'allow', 104, undef, undef),
            acl_row(60,  81, 'allow', 105, undef, undef),

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
    'ACL object 4 (id=15): to_hash returns the right information (namely, no ACLs - interface does not exist)'
);



$acl = OESS::ACL->new( interface_id => undef, db => $db );

cmp_deeply(
    $acl->to_hash(),
    {
        interface_id => undef,
        acls => [
        ],
    },
    'ACL object 5 (id=undef): to_hash returns the right information (namely, no ACLs - no interface_id)'
);



$acl = OESS::ACL->new( interface_id => 21, db => $db );

warn Dumper($acl->to_hash());

cmp_deeply(
    $acl->to_hash(),
    {
        interface_id => 21,
        acls => [
{
                        'eval_position' => '20',
                        'workgroup_id' => '31',
                        'allow_deny' => 'allow',
                        'entity_id' => '11',
                        'end' => '4095',
                        'start' => '-1'
},
{
                        'eval_position' => '30',
                        'workgroup_id' => '31',
                        'allow_deny' => 'allow',
                        'entity_id' => '12',
                        'end' => '4095',
                        'start' => '-1'
}
        ],
    },
    'ACL object 6 (id=21): to_hash returns the right information, even when interface_acl_ids aren\'t in desired order'
);
