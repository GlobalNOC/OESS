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

use Test::More tests => 13;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $interfaces = $db->get_node_interfaces( node => 'Node 1');

my $is_broken = 0;
foreach my $interface (@$interfaces){
    if($interface->{'vlan_tag_range'} eq '1-4095'){
	
    }else{
	$is_broken = 1;
    }

}

ok($is_broken == 0, "All interfaces have vlan range 1-4095");

my $res = $db->update_interface_vlan_range( interface_id => $interfaces->[0]->{'interface_id'}, vlan_tag_range => '100-200');

ok($res == 1, "Says it was successful updating vlan range");

my $interface = $db->get_interface( interface_id => $interfaces->[0]->{'interface_id'});

ok($interface->{'vlan_tag_range'} eq '100-200', "VLAN Range was updated in the DB");

my $is_external_vlan_avail = $db->is_external_vlan_available_on_interface( vlan => 150, interface_id => $interfaces->[0]->{'interface_id'});

ok($is_external_vlan_avail == 1, "Allowed a vlan in the range");

$is_external_vlan_avail = $db->is_external_vlan_available_on_interface( vlan=> 200,interface_id =>$interfaces->[0]->{'interface_id'});

ok($is_external_vlan_avail == 1, "Allowed a vlan at the edge of the range");

$is_external_vlan_avail = $db->is_external_vlan_available_on_interface( vlan=> 100,interface_id =>$interfaces->[0]->{'interface_id'});

ok($is_external_vlan_avail == 1, "Allowed a vlan in the beginning of the range");

$is_external_vlan_avail = $db->is_external_vlan_available_on_interface( vlan=> 1050,interface_id =>$interfaces->[0]->{'interface_id'});

ok($is_external_vlan_avail == 0, "Not allowed outside of the range");

$is_external_vlan_avail = $db->is_external_vlan_available_on_interface( vlan=> 50,interface_id =>$interfaces->[0]->{'interface_id'});

ok($is_external_vlan_avail == 0, "Not allowed outside of the range");

$res = $db->update_interface_vlan_range( interface_id => $interfaces->[1]->{'interface_id'}, vlan_tag_range => 'foo-200');

ok($res == 0, "Says it was not successfull updating the range to non-integer format");

$interface = $db->get_interface( interface_id => $interfaces->[1]->{'interface_id'});

ok($interface->{'vlan_tag_range'} ne 'foo-200', "Vlan range was not updated");

$res = $db->update_interface_vlan_range( interface_id => $interfaces->[1]->{'interface_id'}, vlan_tag_range => '-1,1-4095');

ok($res == 1, "Says update was successful");

$interface = $db->get_interface( interface_id => $interfaces->[1]->{'interface_id'});

ok($interface->{'vlan_tag_range'} eq '-1,1-4095', "Vlan range was updated to include untagged");

$is_external_vlan_avail = $db->is_external_vlan_available_on_interface( vlan => -1, interface_id => $interfaces->[1]->{'interface_id'} );

ok($is_external_vlan_avail == 1, "Untagged interface supported");
