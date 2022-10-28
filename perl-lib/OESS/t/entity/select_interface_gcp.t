#!/usr/bin/perl -T

use strict;
use warnings;

use Data::Dumper;
use Test::Deep;
use Test::More tests => 7;

use OESS::Interface;
use OESS::Entity;

my $i1 = new OESS::Interface(
    model => {
        name => 'i1',
        interface_id => 1,
        node => 'node1',
        cloud_interconnect_id => 'https://www.googleapis.com/compute/v1/demo-gcipartner/gci-demo-10g-zone1',
        cloud_interconnect_type => 'gcp-partner-interconnect',
        description => 'i1',
        acls => [new OESS::ACL(
            model => {
                workgroup_id  => 1,
                interface_id  => 1,
                allow_deny    => 'allow',
                eval_position => 10,
                start => 1,
                end   => 5,
                notes => '',
                entity_id => 1
            }
        )],
        mpls_vlan_tag_range => '1-20',
        used_vlans => [1,3,4],
        operational_state => 'active',
        workgroup_id => 1
    }
);
my $i2 = new OESS::Interface(
    model => {
        name => 'i2',
        interface_id => 2,
        node => 'node1',
        cloud_interconnect_id => 'https://www.googleapis.com/compute/v1/demo-gcipartner/gci-demo-10g-zone2',
        cloud_interconnect_type => 'gcp-partner-interconnect',
        description => 'i2',
        acls => [new OESS::ACL(
            model => {
                workgroup_id  => 1,
                interface_id  => 2,
                allow_deny    => 'allow',
                eval_position => 10,
                start => 1,
                end   => 5,
                notes => '',
                entity_id => 1
            }
        )],
        mpls_vlan_tag_range => '1-20',
        used_vlans => [1,3,4],
        operational_state => 'active',
        workgroup_id => 1
    }
);

my $entity = new OESS::Entity(
    model => {
        name => 'entity',
        description => 'entity',
        logo_url => '',
        url => '',
        interfaces => [$i1, $i2],
        parents => undef,
        children => [],
        entity_id => 1,
        users => []
    }
);

my $intf;
my $intf_err;
my $id = "00000000-0000-0000-0000-000000000000/us-east1/2";

($intf, $intf_err) = $entity->select_interface(workgroup_id => 1, tag => 10, cloud_account_id => $id);
ok(!defined $intf, "Can't lookup interface with out-of-range tag.");

($intf, $intf_err) = $entity->select_interface(workgroup_id => 1, tag => 4, cloud_account_id => $id);
ok(!defined $intf, "Can't lookup interface with in-use tag.");


($intf, $intf_err) = $entity->select_interface(workgroup_id => 1, tag => 5, cloud_account_id => $id);
ok(defined $intf, "Can lookup first interface with valid tag.");

ok($intf->{interface_id} == 2, 'Verified first interface_id.');


($intf, $intf_err) = $entity->select_interface(workgroup_id => 1, tag => 5, cloud_account_id => $id);
ok(!defined $intf, "Can't lookup second interface with reserved tag.");


$id = "00000000-0000-0000-0000-000000000000/us-east1/1";

($intf, $intf_err) = $entity->select_interface(workgroup_id => 1, tag => 5, cloud_account_id => $id);
ok(defined $intf, "Can lookup second interface with other cloud_account_id.");

ok($intf->{interface_id} == 1, 'Verified second interface_id.');
