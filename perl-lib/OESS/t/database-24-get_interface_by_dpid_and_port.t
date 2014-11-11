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
use OESSDatabaseTester;

use Test::More tests => 5;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $res = $db->get_interface_by_dpid_and_port( port_number => 673 );
ok(!defined($res), "failed to fetch interface without dpid");

$res = $db->get_interface_by_dpid_and_port( dpid => 155568807680 );
ok(!defined($res), "failed to fetch interface without port number");

$res = $db->get_interface_by_dpid_and_port( port_number => 673, dpid => 155568803584 );
ok(defined($res), "Interface fetched successfully");

$res = $db->get_interface_by_dpid_and_port( port_number => 99999999, dpid => 155568807680 );
ok(!defined($res), "failed to fetch interface for non-existent porn number");

$res = $db->get_interface_by_dpid_and_port( port_number => 673, dpid => 99999999 );
ok(!defined($res), "failed to fetch interface for non-existent dpid");
