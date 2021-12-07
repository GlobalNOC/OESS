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
use Test::More tests => 5;

use OESSDatabaseTester;

use OESS::DB;
use OESS::Interface;


OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);


my $db = new OESS::DB(
    config  => "$path/../conf/database.xml"
);

my $intf = new OESS::Interface(
    db => $db,
    interface_id => 511,
    bandwidth_validator_config => "$path/../conf/interface-speed-config.xml"
);
ok($intf->interface_id eq '511', 'Correct interface_id');
ok($intf->is_bandwidth_valid(bandwidth => 0) == 1, 'Correct bandwidth validation for normal interface returned');
ok($intf->is_bandwidth_valid(bandwidth => 1000) == 0, 'Correct bandwidth validation for normal interface returned');

$intf->{cloud_interconnect_type} = 'aws-hosted-connection';
$intf->update_db;

ok($intf->is_bandwidth_valid(bandwidth => 0) == 0, 'Correct bandwidth validation for cloud interface returned');
ok($intf->is_bandwidth_valid(bandwidth => 1000) == 1, 'Correct bandwidth validation for cloud interface returned');
