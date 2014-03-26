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

use Test::More tests => 4;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $users = $db->get_users();

ok(defined($users), "returned a value from get_users with no params");
warn Dumper($users);
ok($#{$users} == 89, "Total number of users was 89, was " . $#{$users});

warn Dumper($users->[0]);

#this should be the system user
cmp_deeply($users->[0], {
            'email_address' => 'user_1@foo.net',
            'user_id' => '1',
            'type' => 'normal',
            'family_name' => 'User 1',
            'auth_name' => [],
            'first_name' => 'User 1'
          }, "User1 data matches");

#find a user with a remote_auth set
cmp_deeply($users->[2], {
            'email_address' => 'user_11@foo.net',
            'user_id' => '11',
            'family_name' => 'User 11',
            'type' => 'normal',
            'auth_name' => [
                             'aragusa'
                           ],
            'first_name' => 'User 11'
	   }, "User 11 data matches");
