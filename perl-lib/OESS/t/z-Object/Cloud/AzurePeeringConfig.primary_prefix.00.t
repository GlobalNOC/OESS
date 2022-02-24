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
use Test::More tests => 12;

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

ok($config->primary_prefix('s1', 'ipv4') eq '192.168.100.248/30', 'Got expected v4 address');
ok($config->primary_prefix('s1', 'ipv6') eq '3ffe:ffff:0000:cd30:0000:0000:0000:0000/126', 'Got expected v6 address');

ok($config->primary_prefix('s1', 'ipv4') eq '192.168.100.248/30', 'Got expected v4 address');
ok($config->primary_prefix('s1', 'ipv6') eq '3ffe:ffff:0000:cd30:0000:0000:0000:0000/126', 'Got expected v6 address');

ok($config->primary_prefix('s2', 'ipv4') eq '192.168.100.252/30', 'Got expected v4 address');
ok($config->primary_prefix('s2', 'ipv6') eq '3ffe:ffff:0000:cd30:0000:0000:0000:0004/126', 'Got expected v6 address');

ok($config->primary_prefix('s2', 'ipv4') eq '192.168.100.252/30', 'Got expected v4 address');
ok($config->primary_prefix('s2', 'ipv6') eq '3ffe:ffff:0000:cd30:0000:0000:0000:0004/126', 'Got expected v6 address');

ok($config->primary_prefix('s3', 'ipv4') eq '192.168.101.0/30', 'Got expected v4 address');
ok($config->primary_prefix('s3', 'ipv6') eq '3ffe:ffff:0000:cd30:0000:0000:0000:0008/126', 'Got expected v6 address');

ok($config->primary_prefix('s3', 'ipv4') eq '192.168.101.0/30', 'Got expected v4 address');
ok($config->primary_prefix('s3', 'ipv6') eq '3ffe:ffff:0000:cd30:0000:0000:0000:0008/126', 'Got expected v6 address');
