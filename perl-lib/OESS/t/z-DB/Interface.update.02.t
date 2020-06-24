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
use Test::More tests => 13;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::Interface;

# Purpose:
#
# Verify interface updates are correctly saved into the database.


OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
   config => "$path/../conf/database.xml"
);

my $model = {
    interface_id => 41,
    name => 'e33/1',
    description => 'e33/1',
    operational_state => 'down',
    role => 'unknown',
    vlan_tag_range => '2-10',
    workgroup_id => 11,
    mpls_vlan_tag_range => '11-21',
    cloud_interconnect_type => 'aws-hosted-connection',
    cloud_interconnect_id => 'dxcon_123456',
    bandwidth => 98765,
    mtu => 9000
};

my $err = OESS::DB::Interface::update(
    db => $db,
    interface => $model
);
ok(!defined $err, 'Interface updated');
warn $err if defined $err;


my $intf = OESS::DB::Interface::fetch(
    db => $db,
    interface_id => 41
);

foreach my $key (keys %$model) {
    ok($intf->{$key} eq $model->{$key}, "got expected $key from db");
}

my $inst_Results = $db->execute_query("SELECT end_epoch, start_epoch FROM interface_instantiation WHERE interface_id=41",[]);
my $resultsSize = @$inst_Results;
ok($resultsSize > 1, "Expected number of instantiations increased");

my $newEnd = -1;
my $newStart = -1;
foreach my $result (@$inst_Results) {
     if ($result->{'end_epoch'} gt $newEnd) {
         $newEnd = $result->{'end_epoch'};
     }
     warn "Error: Repeated Start Epoch $newStart" if $newStart eq $result->{'start_epoch'};
     $newStart = $result->{'start_epoch'};
 }
 ok($newEnd != -1, "Expected the end_epoch of the old instantiation changed from -1");
