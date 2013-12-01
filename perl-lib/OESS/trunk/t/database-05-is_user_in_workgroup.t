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

use Test::More tests => 5;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $is_in_workgroup = $db->is_user_in_workgroup(user_id => 11);
ok(!defined($is_in_workgroup), "no value returned when no workgroup id specified");
my $error = $db->get_error();

$is_in_workgroup = $db->is_user_in_workgroup( workgroup_id => 1);
ok(!defined($is_in_workgroup), "no value returned when no user id specified");

$is_in_workgroup = $db->is_user_in_workgroup( );
ok(!defined($is_in_workgroup), "no value returned when both user_id and workgroup_id are not specified");


$is_in_workgroup = $db->is_user_in_workgroup( workgroup_id => 1, user_id => 11);
ok($is_in_workgroup, "User11 is in workgroup 1");

$is_in_workgroup = $db->is_user_in_workgroup( workgroup_id => 91, user_id => 11);
ok(!$is_in_workgroup, "User11 is not in workgroup 91");
