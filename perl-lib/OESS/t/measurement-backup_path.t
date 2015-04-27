#!/usr/bin/perl -T
#measurement-backup-path.t
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
my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );
my $measure = OESS::Measurement->new(db => $db);
my $data_check = $measure->get_circuit_data('circuit_id'=> 61, 'interface' => 'e15/2', 'start_time'=> 1407346140, 'end_time'=> 1407346200, db => $db)->{'data'}[0]->{'data'}[0][1];

ok($data_check eq '799.633153607747', "Interface has active flows");
