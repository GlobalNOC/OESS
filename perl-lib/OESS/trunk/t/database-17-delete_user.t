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

my $user = $db->delete_user( );
ok(!defined($user), "no value returned when no user id specified");
                
my $error = $db->get_error();
ok(defined($error), "No params were passed and we got an error back");

$user = $db->delete_user( user_id => 111 );
ok(defined($user), "Successfully removed  user");

$user = $db->delete_user( user_id => 999999 );
ok(defined($user), "fails to remove a non-existent user");
