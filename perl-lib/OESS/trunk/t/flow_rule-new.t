#!/usr/bin/perl -T

use strict;

use FindBin;
my $path;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
            $path = $1;
      }
}

use OESS::FlowRule;
use Test::More tests => 6;
use Test::Deep;
use Data::Dumper;

my $flow_rule = OESS::FlowRule->new( );
ok(defined($flow_rule), "Can create a new object with nothing set");

$flow_rule = OESS::FlowRule->new();

