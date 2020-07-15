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

my ($result, $error) = OESS::DB::User::has_system_access(db => $db, username => 'user_251@foo.net', role => 'admin');
ok($result == 1, "Got expected undefined result meaning accepting access");

($result, $error) = OESS::DB::User::has_system_access(db => $db, user_id => 251, role =>'normal');
ok($result == 1, "Got expected undefined result meaning accepting access");

($result, $error) = OESS::DB::User::has_system_access(db => $db, user_id => 251, role => 'read-only');
ok($result == 1, "Got expected undefined result meaning accepting access");

($result, $error) = OESS::DB::User::has_system_access(db=> $db, user_id => 911, role => 'read-only');
ok(defined $error, "Got expected error, $error");

OESS::DB::Workgroup::add_user(db => $db, user_id => 901, workgroup_id => 11, role => 'normal');

($result, $error) = OESS::DB::User::has_system_access(db => $db, user_id => 901, role => 'admin' );
ok(defined $error, "Got expected error, $error");

OESS::DB::Workgroup::edit_user_role(db => $db, user_id => 901, workgroup_id => 11, role => 'read-only');

($result, $error) = OESS::DB::User::has_system_access(db => $db, user_id => 901, role => 'normal');
ok(defined $error, "Got expected error, $error");

($result, $error) = OESS::DB::User::has_system_access(db => $db, user_id => 901, role => 'read-only');
ok($result == 1, "Got Expected undefined result meaning accepting access");
