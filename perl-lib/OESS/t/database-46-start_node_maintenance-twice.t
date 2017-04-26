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
use OESSDatabaseTester;

use Test::More tests => 6;
use Data::Dumper;

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

ok(defined(OESS::Database::ERR_NODE_ALREADY_IN_MAINTENANCE), 'ERR_NODE_ALREADY_IN_MAINTENANCE should be exported');

# We put a random node into maintenance mode
my $res = $db->start_node_maintenance(41, 'a random description');

ok(defined($res), 'we can put a node into maintenance mode');
ok(defined($res->{'node'}) && $res->{'node'}->{'name'} == 'Node 41', 'the right node was put into maintenance mode');

# We try to put the node into maintenance mode while it's already in
# maintenance mode; it should fail
$res = $db->start_node_maintenance(41, 'another random description');

ok(!defined($res), 'putting a node into maintenance mode should fail if it is already in maintenance mode');
ok($db->get_error() eq OESS::Database::ERR_NODE_ALREADY_IN_MAINTENANCE, 'right error should be set for maintenance-in-maintenance attempt');


ok(&OESSDatabaseTester::resetOESSDB(), "Resetting OESS Database");
