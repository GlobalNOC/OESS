#!/usr/bin/perl -T

use strict;
use warnings;
use OESS::FlowRule;

use Test::More tests => 15;
use Test::Deep;

my $flow_rule = OESS::FlowRule->new();

ok(defined($flow_rule), "Flow Rule validates");

$flow_rule = OESS::FlowRule->new(match => {'dl_vlan' => 4000});

ok(defined($flow_rule), "Validated with a good vlan");

$flow_rule = OESS::FlowRule->new(match => {'dl_vlan' => 5000});

ok(!defined($flow_rule), "Does not validate with a bad vlan");

$flow_rule = OESS::FlowRule->new(match => {'in_port' => 5});

ok(defined($flow_rule), "Validates with a good port");

$flow_rule = OESS::FlowRule->new(match => {'in_port' => 700000});

ok(!defined($flow_rule), "Does not Validate with a bad port");

$flow_rule = OESS::FlowRule->new( priority => -1);

ok(!defined($flow_rule), "Does not validate with a bad priority");

$flow_rule = OESS::FlowRule->new( priority => 200);

ok(defined($flow_rule), "Flow rule validates with valid priority");

ok($flow_rule->set_match( {'dl_vlan' => 100,
                        'in_port' => 2}), "Was able to change flow rule match");

cmp_deeply($flow_rule->get_match(),{'dl_vlan' => 100,
                                    'in_port' => 2},"Match was set properly");

ok(!$flow_rule->set_match( {'dl_vlan' => 10000,
                        'in_port' => 2}), "Said it was unable to change the flow rule match with invalid vlan");

cmp_deeply($flow_rule->get_match(),{'dl_vlan' => 100,
                                    'in_port' => 2},"Match is still set properly");

ok($flow_rule->set_priority( 400 ), "was able to set priority");

ok($flow_rule->get_priority() == 400, "actually set priority");

ok(!$flow_rule->set_priority( 400000 ), "was not able to set invalid priority");

ok($flow_rule->get_priority() == 400, "flow priority was correct");
