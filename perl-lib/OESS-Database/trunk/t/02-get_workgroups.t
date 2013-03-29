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
use OESSDatabaseTester;

use Test::More tests => 8;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $workgroups = $db->get_workgroups();

ok(defined($workgroups), "returned a value from get_workgroups with no params");
ok($#{$workgroups} == 24, "Total number of workgroups was 24");

cmp_deeply($workgroups->[0],{
    'workgroup_id' => '1',
    'external_id' => undef,
    'name' => 'Workgroup 1',
    'type' => 'normal'
   }, "Workgroup information matches");

$workgroups = $db->get_workgroups( user_id => 11);

ok(defined($workgroups), "returned a value from get_workgroups with a user_id specified");
ok($#{$workgroups} == 7, "Total number of workgroups was 7");
cmp_deeply($workgroups->[0], {
            'workgroup_id' => '1',
            'external_id' => undef,
            'name' => 'Workgroup 1',
            'type' => 'normal'
   }, "Workgroup information matches for user_id 11");

$workgroups = $db->get_workgroups( user_id => 1);

ok(defined($workgroups), "returned a value from get_workgroups with a user_id specfified but not a member of any workgroups");
ok($#{$workgroups} == -1, "No workgroups were returned");


