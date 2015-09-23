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

my $link_id = 71;
my $link = $db->get_link(link_id => $link_id);
my $description = "description";

$db->_start_transaction();
my $maintenance = $db->start_link_maintenance($link->{'link_id'}, $description);
$db->_commit();

ok($maintenance->{'link'}->{'name'} eq $link->{'name'}, "Expected link name retrieved.");
ok($maintenance->{'link'}->{'id'} == $link->{'link_id'}, "Expected link id retrieved.");
ok($maintenance->{'description'} eq $description, "Expected maintenance description retrieved.");
ok($maintenance->{'end_epoch'} == -1, "Expected maintenance description retrieved.");


my $result = $db->get_link_maintenance($link_id);

ok($result->{'link'}->{'name'} eq $maintenance->{'link'}->{'name'}, "Expected link name retrieved.");
ok($result->{'link'}->{'id'} == $maintenance->{'link'}->{'id'}, "Eexpected link id retrieved.");
ok($result->{'description'} eq $maintenance->{'description'}, "Expected maintenance description retrieved.");
ok($result->{'end_epoch'} == $maintenance->{'end_epoch'}, "Expected maintenance description retrieved.");

my $final = $db->end_link_maintenance($link_id);

ok($final eq "1", "Maintenance cleaned up.");
