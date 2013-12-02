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
use Log::Log4perl;

Log::Log4perl::init_and_watch('t/conf/logging.conf',10);

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ckt = OESS::Circuit->new( circuit_id => 1601, db => $db);

my $flows = $ckt->get_flows();

ok(scalar(@$flows) == 2, "Total number of flows match");

warn Dumper($flows);

my $first_flow = OESS::FlowRule->new( dpid => 155569081856,
                                      match => {'dl_vlan' => 3005,
                                                'in_port' => 673},
                                      actions => [{'set_vlan_vid' => 3005},
                                                  {'output' => 675}]);

ok($first_flow->compare_flow( flow_rule => $flows->[0]), "First Flow matches");

 
my $second_flow = OESS::FlowRule->new( dpid => 155569081856,
                                       match => {'dl_vlan' => 3005,
                                                 'in_port' => 675},
                                       actions => [{'set_vlan_vid' => 3005},
                                                   {'output' => 673}]);

ok($second_flow->compare_flow( flow_rule => $flows->[1]), "Second flow matches");
