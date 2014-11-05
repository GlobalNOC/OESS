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

use Test::More tests => 2;
use Test::Deep;
use Data::Dumper;
use Log::Log4perl;

Log::Log4perl::init_and_watch('t/conf/logging.conf',10);

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ckt = OESS::Circuit->new( circuit_id => 1601, db => $db);

my $flows = $ckt->get_flows();

is(scalar(@$flows), 2, "Total number of flows match");

my $expected_flows = [];
push(@$expected_flows, OESS::FlowRule->new( 
    dpid => 155569081856,
    match => {
        'dl_vlan' => 3005,
        'in_port' => 673
    },
    actions => [
        {'set_vlan_vid' => 3005},
        {'output' => 675}
    ]
));
push(@$expected_flows, OESS::FlowRule->new( 
    dpid => 155569081856,
    match => {
        'dl_vlan' => 3005,
        'in_port' => 675
    },
    actions => [
        {'set_vlan_vid' => 3005},
        {'output' => 673}
    ]
));

# make sure they all match
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
        #last;
    }
}

foreach my $expected_flow (@$expected_flows){
    warn "Expected: " . $expected_flow->to_human();
}

ok(!$failed_flow_compare, "flows match!");
