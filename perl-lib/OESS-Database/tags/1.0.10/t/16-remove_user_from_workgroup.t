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

my $user = 11;
my $workgroup = 1;

my $res = $db->remove_user_from_workgroup( user_id => $user );
ok(!defined($res), "fails to remove without workgroup specified");

$res = $db->remove_user_from_workgroup( workgroup_id => $workgroup);
ok(!defined($res), "fails to remove without user specified");

$res = $db->remove_user_from_workgroup( workgroup_id => $workgroup, user_id => $user );
ok(defined($res), "successfully removed user from workgroup");

$res = $db->remove_user_from_workgroup( user_id => 999999, workgroup_id => $workgroup);
ok(!defined($res), "fails to remove a non-existent user from a workgroup");

$res = $db->remove_user_from_workgroup( user_id => $user, workgroup_id => 9999999 );
ok(!defined($res), "fails to remove user from a non-existent workgroup");
