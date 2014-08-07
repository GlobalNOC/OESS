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
use Data::Dumper;

use Test::More tests => 1;
use Test::Deep;
my $timestamp  = 1407331920;
my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );
my $measure = OESS::Measurement->new(db => $db);
my $data_check = $measure->get_circuit_data('circuit_id'=>4011, 'start_time'=> $timestamp, 'end_time'=> 1407331980, db => $db)->{'data'}[0]->{'data'}[0][1];
ok($data_check eq '791.135635317258', "Interface has active flows");
