#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
my $path;

BEGIN {
    if ($FindBin::Bin =~ /(.*)/) {
        $path = $1;
    }
}
use lib "$path/..";

use Data::Dumper;
use Test::More tests => 5;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::Workgroup;

# Purpose:
#
# Verify user creation errors when bad type specified.

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
    config => "$path/../conf/database.xml"
);


my ($id, $err) = OESS::DB::Workgroup::add_user(db => $db,
                                          user_id      => 911,
                                          workgroup_id => 1,
                                          role         => 'normal');
ok(defined $id, "User was added to workgroup");
my $result = $db->execute_query("SELECT * FROM user_workgroup_membership WHERE user_id = 911 AND  workgroup_id = 1");
ok(defined $result && defined $result->[0], "This user existed in the user_workgroup_membership table");
($id, $err) = OESS::DB::Workgroup::remove_user(db => $db,
                                          user_id      => 911,
                                          workgroup_id => 1);
ok(defined $id, "User was removed from workgroup");
ok(!defined $err, "No err was found during removing user to workgroup");
$result = $db->execute_query("SELECT * FROM user_workgroup_membership WHERE user_id = 911 AND workgroup_id = 1");
ok(!defined $result || !defined $result->[0], "This user, workgroup combo no longer exists in the user_workgroup_membership table");
