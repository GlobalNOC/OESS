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

my $result = OESS::DB::User::has_workgroup_access(db => $db, username => 'user_911@foo.net', workgroup_id => 1, role => 'normal');
ok(!defined $result, "Got expected undefined meaning user has access on workgroup");

$result = OESS::DB::User::has_workgroup_access(db => $db, user_id => 911, workgroup_id => 1, role => 'admin');
ok(defined $result->{error}, "Got expected error, $result->{error}");

$result = OESS::DB::User::has_workgroup_access(db => $db, user_id =>251, workgroup_id => 1, role => 'admin');
ok(!defined $result, "Got expected undefined since user is a sysadmin");

OESS::DB::Workgroup::add_user(db => $db, user_id => 911, workgroup_id => 11, role => 'normal');

$result = OESS::DB::User::has_workgroup_access(db => $db, user_id => 911, workgroup_id => 11, role => 'admin');
ok(defined $result->{error}, "Got expected error, user is a system admin but doesn't have proper role in that admin group");

$result = OESS::DB::User::has_workgroup_access(db => $db, user_id => 251, workgroup_id => 11, role => 'admin');
ok(!defined $result, "Got expected undefined since has system admin has proper admin privileges");

OESS::DB::Workgroup::remove_user(db => $db, user_id => 911, workgroup_id => 1);
OESS::DB::Workgroup::remove_user(db => $db, user_id => 911, workgroup_id => 11);

$result = OESS::DB::User::has_workgroup_access(db => $db, user_id => 911, workgroup_id => 1, role => 'read-only');
ok(defined $result->{error}, "Got expected error, $result->{error}");
