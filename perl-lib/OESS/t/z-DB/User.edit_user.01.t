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
use Test::More tests => 28;

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
my $model = {
    given_names => 'Testerfield',
    family_name => 'Testerton',
    email       => 'ttesterton@testertonestates.com',
    username    => 'ttesterton',
    status      => 'active'
};

my ($id, $err) = OESS::DB::User::add_user(
    db => $db,
    given_name  => $model->{given_names},
    family_name => $model->{family_name},
    email       => $model->{email},
    auth_names  => $model->{username}
);
ok(defined $id, "User entry was created");

my $user = OESS::DB::User::fetch(db => $db, user_id => $id);
foreach my $key (keys %$model) {
    ok($user->{$key} eq $model->{$key}, "got expected initial $key from db");
}
$model->{family_name} = 'Please-Ignore';


my ($res, $err2) = OESS::DB::User::edit_user(
    db => $db,
    user_id     => $id,
    given_name  => $model->{given_names},
    family_name => $model->{family_name},
    email       => $model->{email},
    auth_names  => [ $model->{username}, 'ttesterton2', 'ttesterton3' ],
    status      => $model->{status}
);
print ("ERR = $err2") if defined $err2;
ok($res == 1, "Editing User was successful");


my $index = { 'ttesterton' => 962, 'ttesterton2' => 963, 'ttesterton3' => 964 };
my $users = $db->execute_query("select * from remote_auth where user_id=?", [$id]);


foreach my $user (@$users) {
    my $name = $user->{auth_name};
    my $uid = $user->{auth_id};
    ok(defined $index->{$name}, "found expected username $name");
    ok($index->{$name} == $uid, "found expected user id $uid");
    delete $index->{$name};
}

ok(keys %$index == 0, "all expected usernames accounted for");


my ($res3, $err3) = OESS::DB::User::edit_user(
    db => $db,
    user_id     => $id,
    given_name  => $model->{given_names},
    family_name => $model->{family_name},
    email       => $model->{email},
    auth_names  => [ $model->{username}, 'ttesterton3' ],
    status      => $model->{status}
);
print ("ERR = $err3") if defined $err3;
ok($res3 == 1, "Editing User was successful");

$index = { 'ttesterton' => 962, 'ttesterton3' => 964 };
$users = $db->execute_query("select * from remote_auth where user_id=?", [$id]);

foreach my $user (@$users) {
    my $name = $user->{auth_name};
    my $uid = $user->{auth_id};
    ok(defined $index->{$name}, "found expected username $name");
    ok($index->{$name} == $uid, "found expected user id $uid");
    delete $index->{$name};
}

ok(keys %$index == 0, "all expected usernames accounted for");


my ($res4, $err4) = OESS::DB::User::edit_user(
    db => $db,
    user_id     => $id,
    given_name  => $model->{given_names},
    family_name => $model->{family_name},
    email       => $model->{email},
    auth_names  => [ $model->{username}, 'ttesterton3', 'ttesterton4' ],
    status      => $model->{status}
);
print ("ERR = $err4") if defined $err4;
ok($res4 == 1, "Editing User was successful");

$index = { 'ttesterton' => 962, 'ttesterton3' => 964,  'ttesterton4' => 965 };
$users = $db->execute_query("select * from remote_auth where user_id=?", [$id]);

foreach my $user (@$users) {
    my $name = $user->{auth_name};
    my $uid = $user->{auth_id};
    ok(defined $index->{$name}, "found expected username $name");
    ok($index->{$name} == $uid, "found expected user id $uid");
    delete $index->{$name};
}

ok(keys %$index == 0, "all expected usernames accounted for");
