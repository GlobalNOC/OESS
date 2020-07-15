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
use Test::More tests => 8;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::Workgroup;
use OESS::DB::User;
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
my ($user, $uError) = OESS::DB::User::add_user(db => $db,
                                                  given_name  => 'asdfsdfsf',
                                                  family_name => 'baserxdvzxdsfa',
                                                  email       => 'doesntexist@foo.net',
                                                  auth_names  => ['doesntexist@foo.net','doesntexist']);
my $model = { name=> 'blah' };
my ($workgroup, $wError) = OESS::DB::Workgroup::create(db => $db, model => $model);

my ($id, $err) = OESS::DB::Workgroup::add_user(db => $db,
                                                user_id => $user);
ok(!defined $id, "Fails to add without workgroup specified");

($id, $err) = OESS::DB::Workgroup::add_user(db => $db,
                                             workgroup_id => $workgroup);
ok(!defined $id, "Fails to add without user specified");

($id, $err) = OESS::DB::Workgroup::add_user(db => $db,
                                             workgroup_id => $workgroup,
                                             user_id      => $user);
ok(!defined $id, "Fails to add without role specified");


($id, $err) = OESS::DB::Workgroup::add_user(db => $db,
                                          user_id      => $user,
                                          workgroup_id => $workgroup,
                                          role         => 'normal');
ok(defined $id, "User was added to workgroup");
ok(!defined $err, "No err was found during adding user to workgroup");

my $result = $db->execute_query("SELECT * FROM user_workgroup_membership WHERE user_id = ? AND workgroup_id = ?", [$user,$workgroup]);
ok(defined $result && defined $result->[0], "User,Workgroup combo was present in user_workgroup_membership table");

($id, $err) = OESS::DB::Workgroup::add_user(db => $db,
                                            user_id      => 9999999999,
                                            workgroup_id => $workgroup,
                                            role         => 'read-only');
ok(!defined $id, "Fails to add a non-existent user to a workgroup");

($id, $err) = OESS::DB::Workgroup::add_user(db => $db,
                                            user_id      => $user,
                                            workgroup_id => 99999999,
                                            role         => 'admin');
ok(!defined $id, "Fails to add a user to a nonexistent workgroup");
