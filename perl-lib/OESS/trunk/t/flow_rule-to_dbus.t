#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use OESS::FlowRule;

use Test::More tests => 3;
use Test::Deep;


my $flow_mod = OESS::FlowRule->new( match => {'dl_vlan' => 100,
					      'in_port' => 678,
                                              'dl_dst' => 2114071831770928,
                                              'dl_type' => 560320},
				    actions => [{'output' => 679},
						{'set_vlan_vid' => 101},
						{'output' => 1},
						{'set_vlan_vid' => 101}],
				    dpid => 1111111111);

my ($dpid,$match,$action) = $flow_mod->to_dbus();
ok(defined($dpid),"DPID was defined");
ok(defined($match), "Match was defined");
ok(defined($action), "Action was defined");
