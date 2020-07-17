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
use Test::More tests => 10;

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

my $model ={
    given_name  => 'Testerfield',
    family_name => 'Testerton',
    email       => 'ttesterton@testertonestates.com',
    auth_names  => 'ttesterton'
};

my ($id, $err) = OESS::DB::User::add_user();
ok(!defined $id, "No Value returned when no params given");
ok(defined $err, "No params were passed and we got an error back");

($id, $err) = OESS::DB::User::add_user( db => $db, given_name => 'Testerfield' );
ok(!defined $id, "No Value was returned when only given name specified");

($id, $err) = OESS::DB::User::add_user( db => $db, family_name => 'Testerton' );
ok(!defined $id, "No Value was returned when only family name specified");

($id, $err) = OESS::DB::User::add_user( db => $db, email => 'ttesterton@testertonestates.com' );
ok(!defined $id, "No Value was returned when only email specified");

($id, $err) = OESS::DB::User::add_user( db => $db,
                                        family_name => 'Testerton',
                                        given_name  => 'Testerfield');
ok(!defined $id, "No Value was returned when given name and family name specified");


($id, $err) = OESS::DB::User::add_user(db => $db, 
                                          given_name  => $model->{given_name},
                                          family_name => $model->{family_name},
                                          email       => $model->{email},
                                          auth_names  => $model->{auth_names});
ok(defined $id && $id == 922, "New user created with only 1 auth_name specified");

my $user = OESS::DB::User::fetch(db => $db, user_id => $id);

is($user->{status}, 'active', 'Not specifying status defaults to active.');

($id, $err) = OESS::DB::User::add_user(db => $db,
                                          family_name => 'bar2',
                                          given_name  => 'foo2',
                                          email       => 'foo2@bar2.com',
                                          auth_names  => ['foo2', 'foo2@bar.com', 'aasdf3rdf']);
ok(defined $id && $id == 923, "New user created with multiple specified");

$user = OESS::DB::User::fetch(db => $db, user_id => $id);
ok(defined $user, "User exists in the DB");

($id, $err) = OESS::DB::User::add_user(db => $db,
                                          family_name => 'McTester',
                                          given_name  => 'Test',
                                          email       => 'test@testing.com',
                                          auth_names  => '')
