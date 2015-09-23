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

use Test::More tests => 1;
use Data::Dumper;

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $multipoint_circuit_id = 4183;
my $obj_flows = [
    {
        'hard_timeout' => 0,
        'priority' => 32768,
        'actions' => [
            {
                'set_vlan_id' => '100'
            },
            {
                'output' => '1'
            }
            ],
        'idle_timeout' => 0,
        'dpid' => '155568362496',
        'match' => {
            'dl_vlan' => 100,
            'in_port' => '97'
        }
    },
    {
        'hard_timeout' => 0,
        'priority' => 32768,
        'actions' => [
            {
                'set_vlan_id' => '101'
            },
            {
                'output' => '97'
            }
            ],
        'idle_timeout' => 0,
        'dpid' => '155568362496',
        'match' => {
            'dl_vlan' => 101,
            'in_port' => '1'
        }
    },
    {
        'hard_timeout' => 0,
        'priority' => 32768,
        'actions' => [
            {
                'set_vlan_id' => '4'
            },
            {
                'output' => '1'
            }
            ],
        'idle_timeout' => 0,
        'dpid' => '155568803584',
        'match' => {
            'dl_vlan' => 101,
            'in_port' => '98'
        }
    },
    {
        'hard_timeout' => 0,
        'priority' => 32768,
        'actions' => [
            {
                'set_vlan_id' => '4'
            },
            {
                'output' => '673'
            },
            {
                'set_vlan_id' => '5'
            },
            {
                'output' => '673'
            },
            {
                'set_vlan_id' => '6'
            },
            {
                'output' => '673'
            },
            {
                'set_vlan_id' => '7'
            },
            {
                'output' => '673'
            }
            ],
        'idle_timeout' => 0,
        'dpid' => '155569035008',
        'match' => {
            'dl_vlan' => 100,
            'in_port' => 1
        }
    },
    {
        'hard_timeout' => 0,
        'priority' => 32768,
        'actions' => [
            {
                'set_vlan_id' => '100'
            },
            {
                'output' => '98'
            }
            ],
        'idle_timeout' => 0,
        'dpid' => '155568803584',
        'match' => {
            'dl_vlan' => 4,
            'in_port' => '1'
        }
    },
    {
        'hard_timeout' => 0,
        'priority' => 32768,
        'actions' => [
            {
                'set_vlan_id' => '101'
            },
            {
                'output' => '1'
            }
            ],
        'idle_timeout' => 0,
        'dpid' => '155569035008',
        'match' => {
            'dl_vlan' => 4,
            'in_port' => '673'
        }
    },
    {
        'hard_timeout' => 0,
        'priority' => 32768,
        'actions' => [
            {
                'set_vlan_id' => '101'
            },
            {
                'output' => '1'
            }
            ],
        'idle_timeout' => 0,
        'dpid' => '155569035008',
        'match' => {
            'dl_vlan' => 5,
            'in_port' => '673'
        }
    },
    {
        'hard_timeout' => 0,
        'priority' => 32768,
        'actions' => [
            {
                'set_vlan_id' => '101'
            },
            {
                'output' => '1'
            }
            ],
        'idle_timeout' => 0,
        'dpid' => '155569035008',
        'match' => {
            'dl_vlan' => 6,
            'in_port' => '673'
        }
    },
    {
        'hard_timeout' => 0,
        'priority' => 32768,
        'actions' => [
            {
                'set_vlan_id' => '101'
            },
            {
                'output' => '1'
            }
            ],
        'idle_timeout' => 0,
        'dpid' => '155569035008',
        'match' => {
            'dl_vlan' => 7,
            'in_port' => '673'
        }
    }];

# create flow rule objects out of our raw array of hashses
my $flows = [];
foreach my $flow (@$obj_flows) {
    my $tflow = OESS::FlowRule->new(%$flow);
    push(@$flows, $tflow);
}

my $ckt = OESS::Circuit->new( circuit_id => $multipoint_circuit_id, db => $db);
my $actual_flows = $ckt->get_flows();

ok(OESSDatabaseTester::flows_match( 
    actual_flows   => $actual_flows,
    expected_flows => $flows
), "Flows are as expected");
