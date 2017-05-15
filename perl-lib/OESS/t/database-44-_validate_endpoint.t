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
use Test::Deep;
use Data::Dumper;


my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );


# TODO Remove and move into database-29-update_interface_owner.t
my $success = $db->update_interface_owner(interface_id => 51,
                                          workgroup_id => 263);
my $error = $db->get_error();
if(defined($error)){
    warn Dumper($error);
}

ok(defined $success, "Trunk interface was associated with admin workgroup.");


my $basic_interface_id = 45571;
my $basic_workgroup_id = 1;
my $basic_vlan_tag_range = "1-4096";

my $trunk_interface_id = 51;
my $trunk_workgroup_id = 263; # Admin workgroup
my $trunk_vlan_tag_range = "1-99,4095";

# TODO Add validation for basic / regular endpoint validation

# Verify correct VLAN range reporting for trunk interfaces
$success = $db->_validate_endpoint(interface_id => $trunk_interface_id,
                                   workgroup_id => 11,
                                   vlan => undef);
$error = $db->get_error();
ok($success eq "1-99,4095", "returned the proper values");
ok(!defined $error, "Error: $error");

$success = $db->_validate_endpoint(interface_id => $trunk_interface_id,
                                   workgroup_id => $trunk_workgroup_id,
                                   vlan => undef);
warn Dumper($success);
ok($success eq $trunk_vlan_tag_range, "VLAN range reported correctly.");

# Verify VLAN validation works as expected for trunk interfaces
$success = $db->_validate_endpoint(interface_id => $trunk_interface_id,
                                   workgroup_id => $trunk_workgroup_id,
                                   vlan => 100);
ok($success == 0, "In range VLAN for trunk interface caused validation failure.");

$success = $db->_validate_endpoint(interface_id => $trunk_interface_id,
                                   workgroup_id => $trunk_workgroup_id,
                                   vlan => 99);
ok($success == 1, "Out of range VLAN for trunk interfacecaused validation success.");
