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

use Test::More tests =>25;
use Test::Deep;
use Data::Dumper;
use Log::Log4perl;

Log::Log4perl::init_and_watch('t/conf/logging.conf',10);

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ckt = OESS::Circuit->new( circuit_id => 4111, db => $db);

my $flows = $ckt->get_flows();

ok(scalar(@$flows) == 24, "Total number of flows match " . scalar(@$flows));

my $first_flow = OESS::FlowRule->new( dpid => 155569091328,
                                      match => {'dl_vlan' => 157,
                                                'in_port' => 1},
                                      actions => [{'set_vlan_vid' => 134},
                                                  {'output' => 193}]);

ok($first_flow->compare_flow( flow_rule => $flows->[0]), "Flow1 matches");

my $second_flow = OESS::FlowRule->new( dpid => 155569091328,
                                       match => {'dl_vlan' => 157,
                                                 'in_port' => 193},
                                       actions => [{'set_vlan_vid' => 150},
                                                   {'output' => 1}]);

ok($second_flow->compare_flow( flow_rule => $flows->[1]),"Flow2 matches");

my $third_flow = OESS::FlowRule->new( dpid => 155568735232,
                                       match => {'dl_vlan' => 150,
                                                 'in_port' => 1},
                                       actions => [{'set_vlan_vid' => 151},
                                                   {'output' => 97}]);

ok($third_flow->compare_flow( flow_rule => $flows->[2]), "Flow3 matches");

my $fourth_flow = OESS::FlowRule->new( dpid => 155568735232,
                                       match => {'dl_vlan' => 150,
                                                 'in_port' => 97},
                                       actions => [{'set_vlan_vid' => 157},
                                                   {'output' => 1}]);

ok($fourth_flow->compare_flow( flow_rule => $flows->[3]),"Flow4 Matches");

my $fifth_flow = OESS::FlowRule->new( dpid => 155568969984,
                                      match => {'dl_vlan' => 134,
                                                'in_port' => 1},
                                      actions => [{'set_vlan_vid' => 157},
                                                  {'output' => 2}]);

ok($fifth_flow->compare_flow( flow_rule => $flows->[4]),"Flow5 Matches");

my $sixth_flow = OESS::FlowRule->new( dpid => 155568969984,
                                      match => {'dl_vlan' => 134,
                                                'in_port' => 2},
                                      actions => [{'set_vlan_vid' => 140},
                                                  {'output' => 1}]);

ok($sixth_flow->compare_flow( flow_rule => $flows->[5]),"Flow6 matches");

my $flow_7 = OESS::FlowRule->new( dpid => 155568799232,
                                  match => {'dl_vlan' => 151,
                                            'in_port' => 193},
                                  actions => [{'set_vlan_vid' => 145},
                                              {'output' => 97}]);

ok($flow_7->compare_flow( flow_rule => $flows->[6]), "Flow7 matches");
                                               


my $flow_8 = OESS::FlowRule->new( 'actions' => [
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
                                  });
ok($flow_8->compare_flow( flow_rule => $flows->[7]),"Flow8 Matches");



my $flow_9 = OESS::FlowRule->new('actions' => [
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
                                 });

ok($flow_9->compare_flow( flow_rule => $flows->[8]),"Flow9 matches");

my $flow_10 = OESS::FlowRule->new(                 'actions' => [
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
                                                   });

ok($flow_10->compare_flow( flow_rule => $flows->[9]), "Flow10 Matches");

my $flow_11 = OESS::FlowRule->new('actions' => [
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
				  });

ok($flow_11->compare_flow( flow_rule => $flows->[10]), "Flow11 matches");

my $flow_12 = OESS::FlowRule->new( 'actions' => [
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
				   });

ok($flow_12->compare_flow( flow_rule => $flows->[11]),"Flow12 matches");

my $flow_13 = OESS::FlowRule->new('actions' => [
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
				  });

ok($flow_13->compare_flow( flow_rule => $flows->[12]), "Flow13 matches");

my $flow_14 = OESS::FlowRule->new( 'actions' => [
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
				   });

ok($flow_14->compare_flow( flow_rule => $flows->[13]),"Flow14 matches");

my $flow_15 = OESS::FlowRule->new( 'actions' => [
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
                            });

ok($flow_15->compare_flow( flow_rule => $flows->[14]),"Flow15 matches");

my $flow_16 = OESS::FlowRule->new( 'actions' => [
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
				   });

ok($flow_16->compare_flow( flow_rule => $flows->[15]), "Flow16 matches");
my $flow_17 = OESS::FlowRule->new( 'actions' => [
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
				   });

ok($flow_17->compare_flow( flow_rule => $flows->[16]), "Flow17 matches");

my $flow_18 = OESS::FlowRule->new( 'actions' => [
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
				   });

ok($flow_18->compare_flow( flow_rule => $flows->[17]), "Flow18 Matches");

my $flow_19 = OESS::FlowRule->new('actions' => [
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
                            });

ok($flow_19->compare_flow( flow_rule => $flows->[18]), "Flow19 Matches");

my $flow_20 = OESS::FlowRule->new( 'actions' => [
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
				   });

ok($flow_20->compare_flow( flow_rule => $flows->[19]), "Flow20 matches");

my $flow_21 = OESS::FlowRule->new( 'actions' => [
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
				   });

ok($flow_21->compare_flow( flow_rule => $flows->[20]), "Flow21 matches");

my $flow_22 = OESS::FlowRule->new('actions' => [
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
				  });

ok($flow_22->compare_flow( flow_rule => $flows->[21]), "Flow22 matches");

my $flow_23 = OESS::FlowRule->new( 'actions' => [
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
				   });

ok($flow_23->compare_flow( flow_rule => $flows->[22]), "Flow23 Matches");

my $flow_24 = OESS::FlowRule->new( 'actions' => [
				       {
                                  'set_vlan_vid' => '2055'
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
				   });

ok($flow_24->compare_flow( flow_rule => $flows->[23]), "Flow24 Matches");
