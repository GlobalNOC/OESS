#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use OESS::FlowRule;

use Test::More tests => 2;
use Test::Deep;


my $flow_mod = OESS::FlowRule->new( match => {'dl_vlan' => 100,
					      'in_port' => 678,
                                              'dl_dst' => 2114071831770928,
                                              'dl_type' => 560320},
				    actions => [{'output' => 679},
						{'set_vlan_vid' => 101},
						{'output' => 1},
						{'set_vlan_vid' => 101}],
				    dpid => 155568807680);

my $str = $flow_mod->to_human();
ok(defined($str), "Flow Mod string was defined");
$flow_mod->set_actions( [{'output' => 679},
                         {'set_vlan_vid' => 101},
                         {'output' => 1},
                         {'set_vlan_vid' => OESS::FlowRule::UNTAGGED}]);

$str = $flow_mod->to_human();

ok(defined($str), "Flow mod string was defined");
