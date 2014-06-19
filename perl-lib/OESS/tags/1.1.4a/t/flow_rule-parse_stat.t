#!/usr/bin/perl -T

use strict;

use FindBin;
my $path;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
            $path = $1;
      }
}

use OESS::FlowRule;
use Test::More tests => 1;
use Test::Deep;
use Data::Dumper;

my $flow_rule = OESS::FlowRule::parse_stat( dpid => 1235465768,
    
                                            stat => {match => {'in_port' => 10,
                                                               'dl_vlan' => 100},
                                                     actions => [{'type' => OESS::FlowRule::OFPAT_OUTPUT,
                                                                  'port' => 1},
                                                                 {'type' => OESS::FlowRule::OFPAT_SET_VLAN_VID,
                                                                  'vlan_vid' => 100}]});
ok(defined($flow_rule), "Can create a new object with a flow stat");

