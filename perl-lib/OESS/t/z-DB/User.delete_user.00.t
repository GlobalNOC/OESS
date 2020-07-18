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
use Test::More tests => 2;

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

my ($id, $err) = OESS::DB::User::add_user(db => $db,
                                          given_name  => $model->{given_name},
                                          family_name => $model->{family_name},
                                          email       => $model->{email},
                                          auth_names  => $model->{auth_names});

ok(defined $id, "User entry was created");
my ($res, $err2) = OESS::DB::User::delete_user(db => $db, user_id => $id);
ok($res == 1, "Delete was successful");
