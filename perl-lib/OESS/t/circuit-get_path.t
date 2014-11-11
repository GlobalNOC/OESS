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

use Test::More tests => 5;
use Test::Deep;
use Data::Dumper;

#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;

Log::Log4perl::init_and_watch('t/conf/logging.conf',10);

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ckt = OESS::Circuit->new( circuit_id => 4111, db => $db);

ok(!defined($ckt->get_path( )), "get Path returned undef when no path defined");

ok($ckt->get_path( path => 'primary'), "was able to get primary path");
ok(scalar(@{$ckt->get_path( path => 'primary')}) == 4, "Total number of links for primary path: " . scalar(@{$ckt->get_path( path => 'primary')}));

ok($ckt->get_path( path => 'backup'), "was able to get backup path");
ok(scalar(@{$ckt->get_path( path => 'backup')}) == 8, "Total number of links for backup path: " . scalar(@{$ckt->get_path( path => 'backup')}));
