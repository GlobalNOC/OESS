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
use OESS::Measurement;
use OESS::Circuit;
use OESSDatabaseTester;

use Test::More tests => 1;
use Test::Deep;
use Data::Dumper;

#needs to be hard coded!
my $timestamp     = 1406662680;
my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );
my $measure = OESS::Measurement->new();
my $ckt = OESS::Circuit->new( circuit_id => 1, db => $db);
my $data_check = $measure->get_circuit_data('circuit_id'=> 1, 'start_time'=> $timestamp, 'end_time'=>$timestamp)->{'data'}[0]->{'data'}[0][1];
ok($data_check eq '145.030227587993', "Interface has active flows");
