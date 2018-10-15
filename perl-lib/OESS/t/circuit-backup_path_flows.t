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

use Test::More tests =>3;
use Test::Deep;
use Data::Dumper;
use Log::Log4perl;

Log::Log4perl::init_and_watch('t/conf/logging.conf',10);

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ckt = OESS::Circuit->new( circuit_id => 4111, db => $db);

my $nodes = $db->get_current_nodes(type => 'openflow');

ok($ckt->has_backup_path(), "Circuit has backup path");

my $flows = $ckt->get_flows();

warn Dumper($flows);

ok(scalar(@$flows) == 26, "Total number of flows match " . scalar(@$flows));

my @expected_flows;

push(@expected_flows, OESS::FlowRule->new( dpid => 155569091328,
                                           match => {'dl_vlan' => 157,
                                                     'in_port' => 1},
                                           actions => [{'set_vlan_vid' => 134},
                                                       {'output' => 193}]));

push(@expected_flows, OESS::FlowRule->new( dpid => 155569091328,
                                       match => {'dl_vlan' => 157,
                                                 'in_port' => 193},
                                       actions => [{'set_vlan_vid' => 150},
                                                   {'output' => 1}]));


push(@expected_flows, OESS::FlowRule->new( dpid => 155568735232,
                                       match => {'dl_vlan' => 150,
                                                 'in_port' => 97},
                                       actions => [{'set_vlan_vid' => 157},
                                                   {'output' => 1}]));



push(@expected_flows, OESS::FlowRule->new( dpid => 155568735232,
                                       match => {'dl_vlan' => 150,
                                                 'in_port' => 1},
                                       actions => [{'set_vlan_vid' => 151},
                                                   {'output' => 97}]));



push(@expected_flows, OESS::FlowRule->new( dpid => 155568969984,
                                      match => {'dl_vlan' => 134,
                                                'in_port' => 1},
                                      actions => [{'set_vlan_vid' => 157},
                                                  {'output' => 2}]));


push(@expected_flows, OESS::FlowRule->new( dpid => 155568969984,
                                      match => {'dl_vlan' => 134,
                                                'in_port' => 2},
                                      actions => [{'set_vlan_vid' => 140},
                                                  {'output' => 1}]));


push(@expected_flows, OESS::FlowRule->new( dpid => 155568799232,
                                  match => {'dl_vlan' => 151,
                                            'in_port' => 193},
                                  actions => [{'set_vlan_vid' => 145},
                                              {'output' => 97}]));

                                               


push(@expected_flows, OESS::FlowRule->new( 'actions' => [
                                      {
                                          'set_vlan_vid' => '152'
                                      },
                                      {
                                          'output' => '193'
                                      }
                                  ],
                                  'idle_timeout' => 0,
                                  'dpid' => '155568799232',
                                  'match' => {
                                      'dl_vlan' => 151,
                                      'in_port' => 97
                                  }));


push(@expected_flows, OESS::FlowRule->new('actions' => [
                                     {
                                         'set_vlan_vid' => '129'
                                     },
                                     {
                                         'output' => '98'
                                     }
                                 ],
                                 'idle_timeout' => 0,
                                 'dpid' => '155568803584',
                                 'match' => {
                                     'dl_vlan' => 144,
                                     'in_port' => 97
                                 }));


push(@expected_flows, OESS::FlowRule->new(                 'actions' => [
                                                       {
                                  'set_vlan_vid' => '134'
                                                       },
                                                       {
                                  'output' => '97'
                                                       }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155568803584',
                                                   'match' => {
                              'dl_vlan' => 144,
                              'in_port' => 98
                                                   }));

push(@expected_flows, OESS::FlowRule->new('actions' => [
				      {
					  'set_vlan_vid' => '144'
				      },
				      {
					  'output' => '97'
				      }
				  ],
				  'idle_timeout' => 0,
				  'dpid' => '155568780288',
				  'match' => {
				      'dl_vlan' => 134,
				      'in_port' => 1
				  }));


push(@expected_flows, OESS::FlowRule->new( 'actions' => [
				       {
                                  'set_vlan_vid' => '141'
				       },
				       {
                                  'output' => '1'
				       }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155568780288',
				   'match' => {
                              'dl_vlan' => 134,
                              'in_port' => 97
				   }));

push(@expected_flows, OESS::FlowRule->new('actions' => [
				      {
					  'set_vlan_vid' => '24'
				      },
				      {
					  'output' => '98'
				      }
				  ],
				  'idle_timeout' => 0,
				  'dpid' => '155569035008',
				  'match' => {
				      'dl_vlan' => 133,
				      'in_port' => 1
				  }));

push(@expected_flows, OESS::FlowRule->new( 'actions' => [
				       {
					   'set_vlan_vid' => '129'
				       },
				       {
					   'output' => '1'
				       }
				   ],
				   'idle_timeout' => 0,
				   'dpid' => '155569035008',
				   'match' => {
				       'dl_vlan' => 133,
				       'in_port' => 98
				   }));


push(@expected_flows, OESS::FlowRule->new( 'actions' => [
                                {
                                  'set_vlan_vid' => '133'
                                },
                                {
                                  'output' => '97'
                                }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569084160',
                 'match' => {
                              'dl_vlan' => 24,
                              'in_port' => 1
                            }));


push(@expected_flows, OESS::FlowRule->new( 'actions' => [
				       {
                                  'set_vlan_vid' => '145'
				       },
				       {
                                  'output' => '1'
				       }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569084160',
				   'match' => {
                              'dl_vlan' => 24,
                              'in_port' => 97
				   }));

push(@expected_flows, OESS::FlowRule->new( 'actions' => [
				       {
                                  'set_vlan_vid' => '144'
				       },
				       {
                                  'output' => '97'
				       }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155568362496',
				   'match' => {
                              'dl_vlan' => 129,
                              'in_port' => 1
				   }));


push(@expected_flows, OESS::FlowRule->new( 'actions' => [
				       {
                                  'set_vlan_vid' => '133'
				       },
				       {
                                  'output' => '1'
				       }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155568362496',
				   'match' => {
                              'dl_vlan' => 129,
                              'in_port' => 97
				   }));

#ok($flow_18->compare_flow( flow_rule => $flows->[17]), "Flow18 Matches");

push(@expected_flows, OESS::FlowRule->new('actions' => [
                                {
                                  'set_vlan_vid' => '151'
                                },
                                {
                                  'output' => '97'
                                }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569081856',
                 'match' => {
                              'dl_vlan' => 145,
                              'in_port' => 2
                            }));

#ok($flow_19->compare_flow( flow_rule => $flows->[18]), "Flow19 Matches");

push(@expected_flows, OESS::FlowRule->new( 'actions' => [
				       {
                                  'set_vlan_vid' => '24'
				       },
				       {
                                  'output' => '2'
				       }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569081856',
				   'match' => {
                              'dl_vlan' => 145,
                              'in_port' => 97
				   }));

#ok($flow_20->compare_flow( flow_rule => $flows->[19]), "Flow20 matches");

push(@expected_flows, OESS::FlowRule->new( 'actions' => [
				       {
                                  'set_vlan_vid' => '150'
				       },
				       {
                                  'output' => '2'
				       }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569080320',
				   'match' => {
                              'dl_vlan' => 4090,
                              'in_port' => '677'
				   }));

#ok($flow_21->compare_flow( flow_rule => $flows->[20]), "Flow21 matches");

push(@expected_flows, OESS::FlowRule->new('actions' => [
				      {
                                  'set_vlan_vid' => '4090'
				      },
				      {
                                  'output' => '677'
				      }
                              ],
                 'idle_timeout' => 0,
                 'dpid' => '155569080320',
				  'match' => {
                              'dl_vlan' => 151,
                              'in_port' => '2'
				  }));

push(@expected_flows, OESS::FlowRule->new( 'actions' => [
				       {
                                           'set_vlan_vid' => '134'
				       },
                                               {
                                                   'output' => '2'
                                               }
                                           ],
                                           'idle_timeout' => 0,
                                           'dpid' => '155568668928',
                                           'match' => {
                                               'dl_vlan' => 2055,
                                               'in_port' => '676'
                                           }));

push(@expected_flows, OESS::FlowRule->new( 'actions' => [
                                               {'set_vlan_vid' => '2055'
                                               },
                                               {
                                                   'output' => '676'
                                               }
                                           ],
                                           'idle_timeout' => 0,
                                           'dpid' => '155568668928',
                                           'match' => {
                                               'dl_vlan' => 140,
                                               'in_port' => '2'
                                           }));

push(@expected_flows, OESS::FlowRule->new(
    'actions' => [
        {'set_vlan_vid' => '4090'},
        {'output' => '677'}
    ],
    'idle_timeout' => 0,
    'dpid' => '155569080320',
    'match' => {
        'dl_vlan' => 152,
        'in_port' => '97'
    }
));

push(@expected_flows, OESS::FlowRule->new(
    'actions' => [
        {'set_vlan_vid' => '2055'},
        {'output' => '676'}
    ],
    'idle_timeout' => 0,
    'dpid' => '155568668928',
    'match' => {
        'dl_vlan' => 141,
        'in_port' => '1'
    }
));

my $failed_flow_compare = 0;
foreach my $actual_flow (@$flows){
    my $found = 0;
    for(my $i=0;$i < scalar(@expected_flows); $i++){

        if($expected_flows[$i]->compare_flow( flow_rule => $actual_flow)) {
            $found = 1;
            splice(@expected_flows, $i,1);
            last;
        }
    }
    if(!$found){
        warn "actual_flow:   ".$actual_flow->to_human();
        $failed_flow_compare = 1;
        #last; 
    }
}

foreach my $expected_flow (@expected_flows){
    warn "Expected: " . $expected_flow->to_human();
}

ok(!$failed_flow_compare, "flows match!");

