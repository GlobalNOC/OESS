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

use Test::More tests => 7;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $res = $db->get_link_by_interface_id();
ok(!defined($res), "No value returned when no interface_id id specified");

my $error = $db->get_error();
ok(defined($error), "No Params were passed and we got an error back");

$res = $db->get_link_by_interface_id( interface_id => 101 );
ok(defined($res), "Ciruit endpoints found are found for the specified ciruit id");

$res = $db->get_link_by_interface_id( interface_id => 99999999 );
ok(!defined($res), "There are no links for the specified interface id that doesn't exist");

$res = $db->get_link_by_interface_id( interface_id => 541 );

ok($#{$res} == 0, "Even a decomed link only shows up once");
ok($res->[0]->{'link_id'} == '71', "Link ID Matches");

$res = $db->get_link_by_interface_id( interface_id => 541, show_decom => 0);
ok($#{$res} == -1, "Requesting no decom for an interface with only a decom works");


