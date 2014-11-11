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

use Test::More tests => 3;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $user = $db->get_user_admin_status( );
warn Dumper ($user);
ok(!@$user, "no value returned when no user id specified");

$user = $db->get_user_admin_status( username => 'user_921@foo.net' );
warn Dumper ($user);
ok(!@$user, "no value returned when user is not a member of an admin workgroup");

$user = $db->get_user_admin_status( username => 'aragusa');
warn Dumper ($user);
ok(@$user, "value returned when aragusa username passed");

