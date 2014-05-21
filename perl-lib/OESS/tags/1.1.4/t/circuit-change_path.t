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

use Test::More tests => 6;
use Test::Deep;
use Data::Dumper;

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ckt = OESS::Circuit->new( circuit_id => 4111, db => $db);

ok($ckt->has_backup_path(),"Circuit has backup path");
ok($ckt->get_active_path() eq 'primary', "Circuit is on primary path");

ok($ckt->change_path(), "Circuit successfully changed path to backup");

ok($ckt->get_active_path() eq 'backup', "Circuit is now on backup path");

ok($ckt->change_path(), "Circuit successfully changed path to primary");

ok($ckt->get_active_path() eq 'primary', "Circuit is now on primary path");
