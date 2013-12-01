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

my $users = $db->get_users_in_workgroup();

ok(!defined($users), "no value returned when no workgroup id specified");
my $error = $db->get_error();

$users = $db->get_users_in_workgroup( workgroup_id => 1);
ok(defined($users), "get_users_in_workgroup wtih workgroup_id specified return results");
ok($#{$users} == 4, "correct number of users in workgroup_id 1 " . $#{$users});
cmp_deeply($users->[0], {
            'email_address' => 'user_11@foo.net',
            'user_id' => '11',
            'family_name' => 'User 11',
            'auth_name' => [
                             'aragusa@grnoc.iu.edu'
                           ],
            'first_name' => 'User 11'
          }, "first user in workgroup data matches");
