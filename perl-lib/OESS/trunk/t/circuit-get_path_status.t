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
use OESS::Database;
use OESS::Circuit;
use OESSDatabaseTester;

use Test::More tests => 4;
use Test::Deep;
use Data::Dumper;

#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ckt = OESS::Circuit->new( circuit_id => 101, db => $db);

ok(!defined($ckt->get_path_status( )), "Path status returned undef when no path defined");

ok($ckt->get_path_status( path => 'primary') == OESS_LINK_UP, "Path is up!!");

ok($ckt->get_path_status( path => 'primary', link_status => {'Link 41' => OESS_LINK_DOWN}) == OESS_LINK_DOWN, "Path is down!");

ok($ckt->get_path_status( path => 'primary', link_status => {'Link 41' => OESS_LINK_UNKNOWN}) == OESS_LINK_UNKNOWN, "Path is unknown!");
