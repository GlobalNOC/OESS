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
use Log::Log4perl;

Log::Log4perl::init_and_watch('t/conf/logging.conf',10);

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ckt = OESS::Circuit->new( circuit_id => 101, db => $db);

ok(!$ckt->has_backup_path(), "Circuit does not have backup path");
ok(!$ckt->is_interdomain(), "Circuit is not an interdomain circuit");

my $flows = $ckt->get_flows();

is(scalar(@$flows), 4, "Total number of flows match");


my $expected_flows = [];

push(@$expected_flows, OESS::FlowRule->new( dpid => 155569080320,
                                      match => {'dl_vlan' => 105,
                                                'in_port' => 674},
                                      actions => [{'set_vlan_vid' => 100},
                                                  {'output' => 1}]));

push(@$expected_flows, OESS::FlowRule->new( dpid => 155569080320,
                                       match => {'dl_vlan' => 101,
                                                 'in_port' => 1},
                                       actions => [{'set_vlan_vid' => 105},
                                                   {'output' => 674}]));

push(@$expected_flows, OESS::FlowRule->new( dpid => 155569068800,
                                      match => {'dl_vlan' => 105,
                                                'in_port' => 674},
                                      actions => [{'set_vlan_vid' => 101},
                                                  {'output' => 2}]));

push(@$expected_flows, OESS::FlowRule->new( dpid => 155569068800,
                                       match => {'dl_vlan' => 100,
                                                 'in_port' => 2},
                                       actions => [{'set_vlan_vid' => 105},
                                                   {'output' => 674}]));

my $failed_flow_compare = 0;
foreach my $actual_flow (@$flows){
    my $found = 0;
    for(my $i=0;$i < scalar(@$expected_flows); $i++){

        if($expected_flows->[$i]->compare_flow( flow_rule => $actual_flow)) {
            $found = 1;
            splice(@$expected_flows, $i,1);
            last;
        }
    }
    if(!$found){
        warn "actual_flow:   ".$actual_flow->to_human();
        $failed_flow_compare = 1;
    }
}

#foreach my $expected_flow (@expected_flows){
#    warn "Expected: " . $expected_flow->to_human();
#}

ok(!$failed_flow_compare, "flows match!");
