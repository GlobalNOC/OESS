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
use Test::More tests => 4;
use Test::Deep;

use OESSDatabaseTester;

use OESS::DB;
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

my ($users, $error) = OESS::DB::User::fetch_all( db => $db );
warn Dumper($users->[0]);
ok(defined $users, "returned a value for fetch_all with no params");

ok($#{$users} == 89, "Total number of users was 89, was " . $#{$users});
                         
cmp_deeply($users->[0], {
            'email' => 'user_1@foo.net',
            'user_id' => '1',
            'family_name' => 'User 1',
            'usernames' => [],
            'given_name' => 'User 1',
            'is_admin' => 0,
            'status' => 'active'
        },  "User1 data matches");

cmp_deeply($users->[2], {
            'email' => 'user_11@foo.net',
            'user_id' => '11',
            'family_name' => 'User 11',
            'usernames' => [
                              'aragusa'
                           ],
            'given_name' => 'User 11',
            'is_admin' => 1,
            'status' => 'active'
        }, "User 11 data matches");
