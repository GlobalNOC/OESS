#!/usr/bin/perl -T

use strict;
use warnings;
use OESS::FlowRule;

use Test::More tests => 12;
use Test::Deep;

my $flow_rule = OESS::FlowRule->new();

ok(defined($flow_rule), "Flow Rule validates");

$flow_rule = OESS::FlowRule->new(match => {'dl_vlan' => 4000},
                                 actions => [{'set_vlan_vid' => 200},
                                             {'output' => 1}]
    );

ok(defined($flow_rule), "Flow rule is defined");

my $flow_rule2 = OESS::FlowRule->new(match => {'dl_vlan' => 4000},
                                  actions => [{'set_vlan_vid' => 200},
                                              {'output' => 2}]);

ok(defined($flow_rule2), "Flow Rule 2 is defined");

my $res = $flow_rule->compare_match( flow_rule => $flow_rule2);

ok($res == 1, "Flow Rules match do match");

$flow_rule2 = OESS::FlowRule->new(match => {'dl_vlan' => 4000},
                                  actions => [{'set_vlan_vid' => 200}]);

ok(defined($flow_rule2), "Flow rule2 defined again");

$res = $flow_rule->compare_match(flow_rule => $flow_rule2);

ok($res == 1, "Flow Rules match do match (but the action does not)");

$flow_rule2 = OESS::FlowRule->new(match => {'dl_vlan' => 4001},
                                  actions => [{'set_vlan_vid' => 200},
                                              {'output' => 1}]);

ok(defined($flow_rule2), "Flow rule 2 defined again");

$res = $flow_rule->compare_match( flow_rule => $flow_rule2);

ok($res == 0, "Flow rules match does not match!");

$flow_rule2 = OESS::FlowRule->new(match => {'dl_vlan' => 4000,
					    'in_port' => 1},
                                  actions => [{'set_vlan_vid' => 200},
                                              {'output' => 1}]);

ok(defined($flow_rule2), "Flow rule 2 was defined again");

$res = $flow_rule->compare_match( flow_rule => $flow_rule2);

ok($res == 0, "Flow rule matches do not match");

$flow_rule = OESS::FlowRule->new(match => {'dl_vlan' => 4000,
					   'in_port' => 1},
				 actions => [{'set_vlan_vid' => 200},
					     {'output' => 1}]);

ok(defined($flow_rule), "Flow rule is defined again");

$res = $flow_rule->compare_match( flow_rule => $flow_rule2);

ok($res == 1, "Flow rule matches match");
