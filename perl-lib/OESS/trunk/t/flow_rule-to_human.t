#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use OESS::FlowRule;

use Test::More tests => 1;
use Test::Deep;


my $flow_mod = OESS::FlowRule->new( match => {'dl_vlan' => 100,
					      'in_port' => 678},
				    actions => [{'output' => 679},
						{'set_vlan_vid' => 101},
						{'output' => 1},
						{'set_vlan_vid' => 101}],
				    dpid => 1111111111);

my $str = $flow_mod->to_human();
ok(defined($str), "FLow Mod string was defined");
