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

my $ckt = OESS::Circuit->new( circuit_id => 101, db => $db);

my $flows = $ckt->get_flows();

ok(scalar(@$flows) == 4, "Total number of flows match");

my $first_flow = OESS::FlowRule->new( dpid => 155569080320,
                                      match => {'dl_vlan' => 105,
                                                'in_port' => 674},
                                      actions => [{'set_vlan_vid' => 100},
                                                  {'output' => 1}]);

ok($first_flow->compare_flow( flow_rule => $flows->[0]), "First Flow matches");

 
my $second_flow = OESS::FlowRule->new( dpid => 155569080320,
                                       match => {'dl_vlan' => 101,
                                                 'in_port' => 1},
                                       actions => [{'set_vlan_vid' => 105},
                                                   {'output' => 674}]);

ok($second_flow->compare_flow( flow_rule => $flows->[1]), "Second flow matches");

my $third_flow = OESS::FlowRule->new( dpid => 155569068800,
                                      match => {'dl_vlan' => 105,
                                                'in_port' => 674},
                                      actions => [{'set_vlan_vid' => 101},
                                                  {'output' => 2}]);

ok($third_flow->compare_flow( flow_rule => $flows->[2]),"Third Flow matches");

my $fourth_flow = OESS::FlowRule->new( dpid => 155569068800,
                                       match => {'dl_vlan' => 100,
                                                 'in_port' => 2},
                                       actions => [{'set_vlan_vid' => 105},
                                                   {'output' => 674}]);

ok($fourth_flow->compare_flow( flow_rule => $flows->[3]),"fourth flow matches");
