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

use Test::More tests => 9;
use Test::Deep;
use Data::Dumper;


my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $node_id = 1;


my $node = $db->get_node_by_id(node_id => $node_id);
my $description = "description";

$db->_start_transaction();
my $maintenance = $db->start_node_maintenance($node_id, $description);
$db->_commit();

ok($maintenance->{'node'}->{'name'} eq $node->{'name'}, "Expected node name retrieved.");
ok($maintenance->{'node'}->{'id'} == $node->{'node_id'}, "Expected node id retrieved.");
ok($maintenance->{'description'} eq $description, "Expected maintenance description retrieved.");
ok($maintenance->{'end_epoch'} == -1, "Expected maintenance description retrieved.");


my $result = $db->get_node_maintenance($node_id);

ok($result->{'node'}->{'name'} eq $maintenance->{'node'}->{'name'}, "Expected node name retrieved.");
ok($result->{'node'}->{'id'} == $maintenance->{'node'}->{'id'}, "Eexpected node id retrieved.");
ok($result->{'description'} eq $maintenance->{'description'}, "Expected maintenance description retrieved.");
ok($result->{'end_epoch'} == $maintenance->{'end_epoch'}, "Expected maintenance description retrieved.");

my $final = $db->end_node_maintenance($node_id);

ok($final eq "1", "Maintenance cleaned up.");
