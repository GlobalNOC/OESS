#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
my $path;

BEGIN {
    if ($FindBin::Bin =~ /(.*)/) {
        $path = $1;
    }
}
use lib "$path/..";


use Data::Dumper;
use Test::More tests => 4;

use OESSDatabaseTester;

use OESS::Config;
use OESS::Entity;
use OESS::DB;
use OESS::Interface;
use OESS::Cloud::BandwidthValidator;



OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

# BEGIN setup
my $db = new OESS::DB(config => "$path/../conf/database.xml");
$db->execute_query("update interface set cloud_interconnect_type='azure-express-route' where interface_id=1");
# END setup


my $intf = new OESS::Interface(db => $db, interface_id => 1);
warn "Can't load interface from test database." if (!defined $intf);

my $validator = new OESS::Cloud::BandwidthValidator(
    config => "$path/../conf/interface-speed-config.xml",
    interface => new OESS::Interface(db => $db, interface_id => 1)
);
$validator->load;

my $ok = $validator->is_bandwidth_valid(bandwidth => 50, is_admin => 0);
ok($ok, "Got a valid bandwidth");

my $ok2 = $validator->is_bandwidth_valid(bandwidth => 5000, is_admin => 0);
ok(!$ok2, "Got an invalid bandwidth");


# BEGIN setup
$db->execute_query("update interface_instantiation set capacity_mbps=100000 where interface_id=1");
# END setup


my $validator2 = new OESS::Cloud::BandwidthValidator(
    config => "$path/../conf/interface-speed-config.xml",
    interface => new OESS::Interface(db => $db, interface_id => 1)
);
$validator2->load;

my $ok3 = $validator2->is_bandwidth_valid(bandwidth => 10000, is_admin => 0);
ok(!$ok3, "Got an invalid bandwidth");

my $ok4 = $validator2->is_bandwidth_valid(bandwidth => 10000, is_admin => 1);
ok($ok4, "Got a valid bandwidth");
