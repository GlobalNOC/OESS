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

use Test::More tests => 7;
use Test::Deep;
use Data::Dumper;
use Log::Log4perl;

Log::Log4perl::init_and_watch('t/conf/logging.conf',10);

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ckt = OESS::Circuit->new( circuit_id => 4181, db => $db);

ok($ckt->has_backup_path(), "Circuit has backup path");
ok(!$ckt->is_interdomain(), "Circuit is not an interdomain circuit");
ok($ckt->is_static_mac(), "Circuit is a static mac circuit");

my $flows = $ckt->get_flows();

ok(defined($flows), "Flows are defined");
is(scalar(@$flows), 58, "The flow count matches " . scalar(@$flows));

my @actual_3way_flows;

foreach my $flow (@$flows){
    if($flow->get_dpid() == 155569035008){
        push(@actual_3way_flows, $flow);
    }
}

my @expected_3way_flows;

push(@expected_3way_flows, OESS::FlowRule->new( 'priority' => 32768,
                                                'actions' => [
                                                    {
                                                        'set_vlan_id' => 105
                                                    },
                                                    {
                                                        'output' => '1'
                                                    },
                                                    {
                                                        'set_vlan_id' => 28
                                                    },
                                                    {
                                                        'output' => '98'
                                                    }
                                                ],
                                                'idle_timeout' => 0,
                                                'dpid' => '155569035008',
                                                'match' => {
                                                    'dl_vlan' => 100,
                                                    'in_port' => 97
                                                }));
push(@expected_3way_flows, OESS::FlowRule->new( 'priority' => 32768,
                                                'actions' => [
                                                    {
                                                        'set_vlan_id' => 101
                                                    },
                                                    {
                                                        'output' => '97'
                                                    },
                                                    {
                                                        'set_vlan_id' => 28
                                                    },
                                                    {
                                                        'output' => '98'
                                                    }
                                                ],
                                                'idle_timeout' => 0,
                                                'dpid' => '155569035008',
                                                'match' => {
                                                    'dl_vlan' => 102,
                                                    'in_port' => 1
                                                }));
push(@expected_3way_flows, OESS::FlowRule->new( 'priority' => 32768,
                                                'actions' => [
                                                    {
                                                        'set_vlan_id' => 101
                                                    },
                                                    {
                                                        'output' => '97'
                                                    },
                                                    {
                                                        'set_vlan_id' => 105
                                                    },
                                                    {
                                                        'output' => '1'
                                                    }
                                                ],
                                                'dpid' => '155569035008',
                                                'match' => {
                                                    'dl_vlan' => 101,
                                                    'in_port' => 98
                                                }));

push(@expected_3way_flows, OESS::FlowRule->new('hard_timeout' => 0,
                 'priority' => 35000,
                 'actions' => [
                     {
                                  'set_vlan_id' => '105'
                     },
                     {
                                  'output' => 1
                     }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569035008',
                                               'match' => {
                              'dl_vlan' => 100,
                              'dl_dst' => '132129489485683',
                              'in_port' => 97
                                               }));

push(@expected_3way_flows, OESS::FlowRule->new('hard_timeout' => 0,
                 'priority' => 35000,
                 'actions' => [
                     {
                                  'set_vlan_id' => '105'
                     },
                     {
                                  'output' => 1
                     }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569035008',
                                               'match' => {
                              'dl_vlan' => 100,
                              'dl_dst' => '132129489485684',
                              'in_port' => 97
                                               }));

push(@expected_3way_flows, OESS::FlowRule->new('hard_timeout' => 0,
                 'priority' => 35000,
                 'actions' => [
                     {
                                  'set_vlan_id' => '105'
                     },
                     {
                                  'output' => 1
                     }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569035008',
                                               'match' => {
                              'dl_vlan' => 100,
                              'dl_dst' => '132129489485685',
                              'in_port' => 97
                                               }));

push(@expected_3way_flows, OESS::FlowRule->new('hard_timeout' => 0,
                 'priority' => 35000,
                 'actions' => [
                     {
                                  'set_vlan_id' => '105'
                     },
                     {
                                  'output' => 1
                     }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569035008',
                                               'match' => {
                              'dl_vlan' => 101,
                              'dl_dst' => '132129489485683',
                              'in_port' => 98
                                               }));

push(@expected_3way_flows, OESS::FlowRule->new('hard_timeout' => 0,
                 'priority' => 35000,
                 'actions' => [
                     {
                                  'set_vlan_id' => '105'
                     },
                     {
                                  'output' => 1
                     }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569035008',
                                               'match' => {
                              'dl_vlan' => 101,
                              'dl_dst' => '132129489485684',
                              'in_port' => 98
                                               }));

push(@expected_3way_flows, OESS::FlowRule->new('hard_timeout' => 0,
                 'priority' => 35000,
                 'actions' => [
                     {
                                  'set_vlan_id' => '105'
                     },
                     {
                                  'output' => 1
                     }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569035008',
                                               'match' => {
                              'dl_vlan' => 101,
                              'dl_dst' => '132129489485685',
                              'in_port' => 98
                                               }));

push(@expected_3way_flows, OESS::FlowRule->new('hard_timeout' => 0,
                 'priority' => 35000,
                 'actions' => [
                     {
                                  'set_vlan_id' => '105'
                     },
                     {
                                  'output' => 1
                     }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569035008',
                                               'match' => {
                              'dl_vlan' => 100,
                              'dl_dst' => '132129489485173',
                              'in_port' => 97
                                               }));

push(@expected_3way_flows, OESS::FlowRule->new('hard_timeout' => 0,
                 'priority' => 35000,
                 'actions' => [
                     {
                                  'set_vlan_id' => '105'
                     },
                     {
                                  'output' => 1
                     }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569035008',
                                               'match' => {
                              'dl_vlan' => 101,
                              'dl_dst' => '132129489485173',
                              'in_port' => 98
                                               }));

push(@expected_3way_flows, OESS::FlowRule->new('hard_timeout' => 0,
                 'priority' => 35000,
                 'actions' => [
                     {
                                  'set_vlan_id' => '28'
                     },
                     {
                                  'output' => 98
                     }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569035008',
                                               'match' => {
                              'dl_vlan' => 100,
                              'dl_dst' => '132129489485440',
                              'in_port' => 97
                                               }));


push(@expected_3way_flows, OESS::FlowRule->new('hard_timeout' => 0,
                 'priority' => 35000,
                 'actions' => [
                     {
                                  'set_vlan_id' => '28'
                     },
                     {
                                  'output' => 98
                     }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569035008',
                                               'match' => {
                              'dl_vlan' => 100,
                              'dl_dst' => '132129489485441',
                              'in_port' => 97
                                               }));

push(@expected_3way_flows, OESS::FlowRule->new('hard_timeout' => 0,
                                               'priority' => 35000,
                                               'actions' => [
                                                   {
                                                       'set_vlan_id' => '28'
                                                   },
                                                   {
                                                       'output' => 98
                                                   }
                                               ],
                                               'idle_timeout' => 0,
                                               'dpid' => '155569035008',
                                               'match' => {
                                                   'dl_vlan' => 102,
                                                   'dl_dst' => '132129489485440',
                                                   'in_port' => 1
                                               }));

push(@expected_3way_flows, OESS::FlowRule->new('hard_timeout' => 0,
                                               'priority' => 35000,
                                               'actions' => [
                                                   {
                                                       'set_vlan_id' => '28'
                                                   },
                                                   {
                                                       'output' => 98
                                                   }
                                               ],
                                               'idle_timeout' => 0,
                                               'dpid' => '155569035008',
                                               'match' => {
                                                   'dl_vlan' => 102,
                                                   'dl_dst' => '132129489485441',
                                                   'in_port' => 1
                                               }));

push(@expected_3way_flows, OESS::FlowRule->new('hard_timeout' => 0,
                 'priority' => 35000,
                 'actions' => [
                     {
                                  'set_vlan_id' => '101'
                     },
                     {
                                  'output' => 97
                     }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569035008',
                                               'match' => {
                              'dl_vlan' => 102,
                              'dl_dst' => '132129489485456',
                              'in_port' => 1
                                               }));

push(@expected_3way_flows, OESS::FlowRule->new('hard_timeout' => 0,
                 'priority' => 35000,
                 'actions' => [
                     {
                                  'set_vlan_id' => '101'
                     },
                     {
                                  'output' => 97
                     }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569035008',
                                               'match' => {
                              'dl_vlan' => 102,
                              'dl_dst' => '132129489485457',
                              'in_port' => 1
                                               }));

push(@expected_3way_flows, OESS::FlowRule->new('hard_timeout' => 0,
                 'priority' => 35000,
                 'actions' => [
                     {
                                  'set_vlan_id' => '101'
                     },
                     {
                                  'output' => 97
                     }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569035008',
                                               'match' => {
                              'dl_vlan' => 101,
                              'dl_dst' => '132129489485456',
                              'in_port' => 98
                                               }));

push(@expected_3way_flows, OESS::FlowRule->new('hard_timeout' => 0,
                 'priority' => 35000,
                 'actions' => [
                     {
                                  'set_vlan_id' => '101'
                     },
                     {
                                  'output' => 97
                     }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569035008',
                                               'match' => {
                              'dl_vlan' => 101,
                              'dl_dst' => '132129489485457',
                              'in_port' => 98
                                               }));

ok($#expected_3way_flows == $#actual_3way_flows ,"expected 3way flows match actual 3way flows");


my $ok= 1;
for(my $i=0;$i<=$#expected_3way_flows;$i++){
    if($actual_3way_flows[$i]->compare_flow( flow_rule => $expected_3way_flows[$i])){
        
    }else{
        warn "FLow: " . $actual_3way_flows[$i]->to_human()  . "does not match : ";# . $expected_3way_flows[$i]->to_human() . "\n";
        $ok = 0;
    }
}

ok($ok, "Actual and expected flows match");
