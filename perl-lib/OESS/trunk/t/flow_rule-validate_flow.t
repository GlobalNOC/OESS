#!/usr/bin/perl -T

use strict;
use warnings;
use OESS::FlowRule;

use Test::More tests => 1;

my $flow_rule = OESS::FlowRule->new();

ok($flow_rule->validate_flow(), "Flow Rule validates");
