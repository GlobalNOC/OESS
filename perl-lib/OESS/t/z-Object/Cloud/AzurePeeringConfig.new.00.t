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
use lib "$path/../..";


use Data::Dumper;
use Test::More tests => 2;

use OESSDatabaseTester;

use OESS::DB;
use OESS::Cloud::AzureStub;
use OESS::Cloud::AzurePeeringConfig;
use OESS::Config;

OESSDatabaseTester::resetOESSDB(
    config => "$path/../../conf/database.xml",
    dbdump => "$path/../../conf/oess_known_state.sql"
);


my $db = new OESS::DB(config => "$path/../../conf/database.xml");


my $config = new OESS::Cloud::AzurePeeringConfig(db => $db);
# warn Dumper($config);

ok($config->{next_v4_prefix}->print eq '192.168.100.248/30', 'Got expected v4 address');
ok($config->{next_v6_prefix}->print eq '3ffe:ffff:0:cd30::/126', 'Got expected v6 address');
