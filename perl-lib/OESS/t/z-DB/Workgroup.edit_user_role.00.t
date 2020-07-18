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
use Test::More tests => 6;

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
ok(!defined $err, "No err was found during adding user to workgroup");

my $result = $db->execute_query("SELECT * FROM user_workgroup_membership WHERE user_id = 911 AND workgroup_id = 1") ;
ok($result->[0]->{role} eq 'normal', "User,Workgroup combo was present in user_workgroup_membership table and has the normal role");

($id, $err) = OESS::DB::Workgroup::edit_user_role(db => $db,
                                          user_id      => 911,
                                          workgroup_id => 1,
                                          role         => 'admin');
ok(defined $id, "User's role was edited");
ok(!defined $err, "No err was found during editing user's role");

$result = $db->execute_query("SELECT * FROM user_workgroup_membership WHERE user_id = 911 AND workgroup_id =1");
ok($result->[0]->{role} eq 'admin', "User,Workgroup combo now has the role of admin");
