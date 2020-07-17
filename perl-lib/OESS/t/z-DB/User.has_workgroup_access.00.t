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
use Test::More tests => 7;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::User;
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

OESS::DB::Workgroup::add_user(db => $db, user_id => 911, workgroup_id => 1, role => 'normal' );

my ($result, $err) = OESS::DB::User::has_workgroup_access(db => $db, username => 'user_911@foo.net', workgroup_id => 1, role => 'normal');
ok(!defined $err, "Got expected undefined err meaning user has access on workgroup");
my $user911_tests = [
    { workgroup_id => 1,  username => 'user_911@foo.net', user_id => 911, role => 'read-only', result => 1, error => 0 },
    { workgroup_id => 1,  username => 'user_911@foo.net', user_id => 911, role => 'normal',    result => 1, error => 0 },
    { workgroup_id => 1,  username => 'user_911@foo.net', user_id => 911, role => 'admin',     result => 0, error => 1 },
    { workgroup_id => 11, username => 'user_911@foo.net', user_id => 911, role => 'read-only', result => 0, error => 1 },
    { workgroup_id => 11, username => 'user_911@foo.net', user_id => 911, role => 'normal',    result => 0, error => 1 },
    { workgroup_id => 11, username => 'user_911@foo.net', user_id => 911, role => 'admin',     result => 0, error => 1 },

    { workgroup_id => 1,  username => 'user_251@foo.net', user_id => 251, role => 'read-only', result => 1, error => 0 },
    { workgroup_id => 1,  username => 'user_251@foo.net', user_id => 251, role => 'normal',    result => 1, error => 0 },
    { workgroup_id => 1,  username => 'user_251@foo.net', user_id => 251, role => 'admin',     result => 1, error => 0 },
    { workgroup_id => 11, username => 'user_251@foo.net', user_id => 251, role => 'read-only', result => 1, error => 0 },
    { workgroup_id => 11, username => 'user_251@foo.net', user_id => 251, role => 'normal',    result => 1, error => 0 },
    { workgroup_id => 11, username => 'user_251@foo.net', user_id => 251, role => 'admin',     result => 1, error => 0 }
];

# Test using user_id                                                                                                                                                                                                                                                             
foreach my $args (@$user911_tests) {
    my ($result, $err) = OESS::DB::User::has_workgroup_access(db => $db, user_id => $args->{user_id}, workgroup_id => $args->{workgroup_id}, role => $args->{role});
    my $error = (defined $err) ? 1 : 0;
    ok($result == $args->{result} && $error == $args->{error}, "has_workgroup_access(user_id => $args->{user_id}, workgroup_id => $args->{workgroup_id}, role => $args->{role}) returned ($result, $error). Want ($args->{result}, $args->{error})");
}

# Test using username                                                                                                                                                                                                                                                            
foreach my $args (@$user911_tests) {
    my ($result, $err) = OESS::DB::User::has_workgroup_access(db => $db, username => $args->{username}, workgroup_id => $args->{workgroup_id}, role => $args->{role});
    my $error = (defined $err) ? 1 : 0;
    ok($result == $args->{result} && $error == $args->{error}, "has_workgroup_access(username => $args->{username}, workgroup_id => $args->{workgroup_id}, role => $args->{role}) returned ($result, $error). Want ($args->{result}, $args->{error})");
}

($result, $err) = OESS::DB::User::has_workgroup_access(db => $db, user_id => 911, workgroup_id => 1, role => 'admin');
ok(defined $err, "Got expected error, $err");

($result, $err) = OESS::DB::User::has_workgroup_access(db => $db, user_id =>251, workgroup_id => 1, role => 'admin');
ok(!defined $err, "Got expected undefined err since user is a sysadmin");

OESS::DB::Workgroup::add_user(db => $db, user_id => 911, workgroup_id => 11, role => 'normal');

($result, $err) = OESS::DB::User::has_workgroup_access(db => $db, user_id => 911, workgroup_id => 11, role => 'admin');
ok(defined $err, "Got expected error, user is a system admin but doesn't have proper role in that admin group");

($result, $err) = OESS::DB::User::has_workgroup_access(db => $db, user_id => 251, workgroup_id => 11, role => 'admin');
ok(!defined $err, "Got expected undefined err since has system admin has proper admin privileges");

OESS::DB::Workgroup::remove_user(db => $db, user_id => 911, workgroup_id => 1);
OESS::DB::Workgroup::remove_user(db => $db, user_id => 911, workgroup_id => 11);

($result, $err) = OESS::DB::User::has_workgroup_access(db => $db, user_id => 911, workgroup_id => 1, role => 'read-only');
ok(defined $err, "Got expected error, $err");

my $model = {
    name => 'Admin Group 2',
    type => 'admin'
};
my ($newWGID, $createErr) = OESS::DB::Workgroup::create(db => $db, model => $model);
OESS::DB::Workgroup::add_user(db => $db, user_id =>911, workgroup_id => $newWGID, role=>'admin');

($result, $err) = OESS::DB::User::has_workgroup_access(db => $db, user_id => 911, workgroup_id => 11, role => 'admin');
ok(!defined $err, "Got expected undefined err since this user is a high admin even though it is not his personal admin group.");
