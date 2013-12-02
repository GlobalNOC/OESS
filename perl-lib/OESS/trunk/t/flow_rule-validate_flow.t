#!/usr/bin/perl -T

use strict;
use warnings;
use OESS::FlowRule;

use Test::More tests => 5;

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
