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
use OESS::DB::ACL;
use OESS::ACL;
use OESSDatabaseTester;

use Test::More tests => 7;
use Test::Deep;
use Data::Dumper;

sub acl_row {
    return {
        eval_position => $_[0],
        workgroup_id  => $_[1],
        workgroup_name=> $_[2],
        allow_deny    => $_[3],
        start         => $_[4],
        end           => $_[5],
        entity_id     => $_[6],
        entity_name   => $_[7],
        interface_id  => $_[8],
        interface_acl_id => $_[9],
        notes         => $_[10]
    };
}


my $db = OESS::DB->new( config => OESSDatabaseTester::getConfigFilePath() );

my $acl = [];
my $raw = OESS::DB::ACL::fetch_all(db => $db, interface_id => 45811);
foreach my $r (@$raw) {
    my $tmp = OESS::ACL->new(db => $db, model => $r);
    warn Dumper($tmp->to_hash());
    push @$acl, $tmp->to_hash();
}

ok(defined($db) && defined($acl), 'Sanity-check: can instantiate OESS::DB and OESS::ACL objects');

cmp_deeply(
    $acl,
    [
        acl_row(10,  21,'Workgroup 21', 'allow', 100, 100, undef, undef, 45811, 3, 'ima note'),
        acl_row(20,  31,'Workgroup 31', 'allow', 101, 101, undef, undef, 45811, 4, 'ima note'),
        acl_row(22, 241,'Workgroup 241', 'allow',   1,  4095, undef, undef, 45811, 19, ''),
        acl_row(30, 101,'Workgroup 101', 'allow', 102, 102, undef, undef, 45811, 5, 'ima note'),
        acl_row(40,  61,'Workgroup 61', 'allow', 103, 103, undef, undef, 45811, 6, 'ima note'),
        acl_row(50,  71,'Workgroup 71', 'allow', 104, 104, undef, undef, 45811, 7, 'ima note'),
        acl_row(60,  81,'Workgroup 81', 'allow', 105, 105, undef, undef, 45811, 8, 'ima note')
    ],
    'OESS::DB::ACL::fetch_all > OESS::ACL > to_hash: returns the right information, in the right order'
);


$acl = [];
$raw = OESS::DB::ACL::fetch_all(db => $db, interface_id => 45901);

foreach my $r (@$raw) {
    my $tmp = OESS::ACL->new(db => $db, model => $r);
    push @$acl, $tmp->to_hash();
}

cmp_deeply(
    $acl,
    [
        acl_row(10, 21,'Workgroup 21', 'deny',  101, 200,  undef, undef, 45901, 1, 'ima note'),
        acl_row(20, 21,'Workgroup 21', 'allow', 120, 125,  undef, undef, 45901, 13, undef),
        acl_row(30, 21,'Workgroup 21', 'allow', -1,  4095, undef, undef, 45901, 14, undef),
    ],
    'OESS::DB::ACL::fetch_all > OESS::ACL > to_hash: returns the right information, in the right order'
);


$acl = [];
$raw = OESS::DB::ACL::fetch_all(db => $db, interface_id => 32291);

foreach my $r (@$raw) {
    my $tmp = OESS::ACL->new(db => $db, model => $r);
    push @$acl, $tmp->to_hash();
}

cmp_deeply(
    $acl,
    [],
    'OESS::DB::ACL::fetch_all > OESS::ACL > to_hash: returns the right information (namely, no ACLs - none in DB)'
);


$acl = [];
$raw = OESS::DB::ACL::fetch_all(db => $db, interface_id => 15);

foreach my $r (@$raw) {
    my $tmp = OESS::ACL->new(db => $db, model => $r);
    push @$acl, $tmp->to_hash();
}

cmp_deeply(
    $acl,
    [],
    'OESS::DB::ACL::fetch_all > OESS::ACL > to_hash: returns the right information (namely, no ACLs - interface does not exist)'
);


$raw = OESS::DB::ACL::fetch_all(db => $db, interface_id => undef);
ok( (scalar @$raw) == 23, 'OESS::DB::ACL::fetch_all returns all acls when no filter is specified');


$acl = [];
$raw = OESS::DB::ACL::fetch_all(db => $db, interface_id => 21);

foreach my $r (@$raw) {
    my $tmp = OESS::ACL->new(db => $db, model => $r);
    push @$acl, $tmp->to_hash();
}

cmp_deeply(
    $acl,
    [
        acl_row(20,  31,'Workgroup 31', 'allow', -1, 4095, 11,'BC US-East', 21, 16, undef),
        acl_row(30,  31,'Workgroup 31', 'allow', -1, 4095, 12,'BC US-West', 21, 17, undef),
    ],
    'OESS::DB::ACL::fetch_all > OESS::ACL > to_hash: returns the right information (namely, 2 ACLs with entity_ids)'
);
