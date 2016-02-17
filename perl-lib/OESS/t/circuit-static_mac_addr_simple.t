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
is(scalar(@$flows), 74, "The flow count matches " . scalar(@$flows));

my $ep_flows = $ckt->get_endpoint_flows( path => 'primary');

is(scalar(@$ep_flows), 12, "The flow count matches " . scalar(@$ep_flows));

my $b_ep_flows = $ckt->get_endpoint_flows( path => 'backup');
is(scalar(@$b_ep_flows), 12, "The flow count matches " . scalar(@$b_ep_flows));
