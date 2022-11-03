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
use Test::More tests => 8;

use OESSDatabaseTester;

use OESS::Config;
use OESS::Entity;
use OESS::DB;
use OESS::Cloud::AzureInterfaceSelector;

{
    package AzureStub;

    sub new {
        my $class = shift;
        my $args = { @_ };
        return bless $args, $class;
    }

    sub expressRouteCrossConnection {
        return {
            'etag' => 'W/"00000000-0000-0000-0000-000000000000"',
            'location' => 'westus',
            'name' => '00000000-0000-0000-0000-000000000000',
            'type' => 'Microsoft.Network/expressRouteCrossConnections',
            'id' => '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/CrossConnection-SiliconValleyTest/providers/Microsoft.Network/expressRouteCrossConnections/00000000-0000-0000-0000-000000000000',
            'properties' => {
                'bandwidthInMbps' => 50,
                'serviceProviderProvisioningState' => 'NotProvisioned',
                'provisioningState' => 'Succeeded',
                'sTag' => 5,
                'peerings' => [],
                'peeringLocation' => 'Silicon Valley Test',
                'expressRouteCircuit' => {
                    'id' => '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-api/providers/Microsoft.Network/expressRouteCircuits/test-1'
                },
                'secondaryAzurePort' => 'AzureTest-SJC-TEST-06GMR-CIS-2-SEC-A',
                'primaryAzurePort' => 'AzureTest-SJC-TEST-06GMR-CIS-1-PRI-A'
            }
        };
    }
}


# my $test_config = new OESS::Config(config_filename => "$path/../conf/database.xml");

# my $azure = new OESS::Cloud::Azure();



warn "resetting";
OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);
warn "reseted";

my $db = new OESS::DB(config => "$path/../conf/database.xml");

$db->start_transaction;
$db->execute_query("insert into entity (name) values ('azure')");
$db->execute_query("
insert into interface_acl (workgroup_id, interface_id, allow_deny, eval_position, vlan_start, vlan_end, entity_id)
values
(1, 45901,'allow', 10, 2, 4094, 124), (1, 45911, 'allow', 10, 2, 4094, 124)");
$db->execute_query("
update interface set cloud_interconnect_type='azure-express-route', cloud_interconnect_id='AzureTest-SJC-TEST-06GMR-CIS-1-PRI-A'
where interface_id=45901;");
$db->execute_query("
update interface set cloud_interconnect_type='azure-express-route', cloud_interconnect_id='AzureTest-SJC-TEST-06GMR-CIS-2-SEC-A'
where interface_id=45911;");
$db->commit;


my $azure = new AzureStub();
my $conn = $azure->expressRouteCrossConnection;

# BEGIN Verify interfaces may be selected one after another
#
my $selector = new OESS::Cloud::AzureInterfaceSelector(
    db => $db,
    entity => new OESS::Entity(db => $db, entity_id => 124),
    service_key => "00000000-0000-0000-0000-000000000000"
);
my $pri = $selector->select_interface($conn);
ok(defined $pri && $pri->{interface_id} == 45901, "Got primary interface");

my $sec = $selector->select_interface($conn);
ok(defined $sec && $sec->{interface_id} == 45911, "Got secondary interface");

my $tri = $selector->select_interface($conn);
ok(!defined $tri, "Got no interface");


# BEGIN Verify if only primary interface in use, secondary is offered
#
my $vrf_ep_id = $db->execute_query("
insert into vrf_ep
(interface_id, tag, inner_tag, bandwidth, vrf_id, state, unit, mtu)
values (45901, 100, 100, 100, 1, 'active', 100, 9000)");

$db->execute_query("
    insert into cloud_connection_vrf_ep
    (vrf_ep_id, cloud_account_id, cloud_connection_id)
    values (?, '00000000-0000-0000-0000-000000000000', '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/CrossConnection-SiliconValleyTest/providers/Microsoft.Network/expressRouteCrossConnections/00000000-0000-0000-0000-000000000000')", [$vrf_ep_id]);

my $selector2 = new OESS::Cloud::AzureInterfaceSelector(
    db => $db,
    entity => new OESS::Entity(db => $db, entity_id => 124),
    service_key => "00000000-0000-0000-0000-000000000000"
);

my $sec2 = $selector2->select_interface($conn);
ok(defined $sec2 && $sec2->{interface_id} == 45911, "Got secondary interface");

my $tri2 = $selector2->select_interface($conn);
ok(!defined $tri2, "Got no interface");


# BEGIN Verify if only secondary interface in use, primary is offered
#
$db->execute_query("delete from cloud_connection_vrf_ep where vrf_ep_id=?", [$vrf_ep_id]);
$db->execute_query("delete from vrf_ep where vrf_ep_id=?", [$vrf_ep_id]);

my $vrf_ep_id3 = $db->execute_query("
insert into vrf_ep
(interface_id, tag, inner_tag, bandwidth, vrf_id, state, unit, mtu)
values (45911, 100, 100, 100, 1, 'active', 100, 9000)");

$db->execute_query("
    insert into cloud_connection_vrf_ep
    (vrf_ep_id, cloud_account_id, cloud_connection_id)
    values (?, '00000000-0000-0000-0000-000000000000', '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/CrossConnection-SiliconValleyTest/providers/Microsoft.Network/expressRouteCrossConnections/00000000-0000-0000-0000-000000000000')", [$vrf_ep_id3]);

my $selector3 = new OESS::Cloud::AzureInterfaceSelector(
    db => $db,
    entity => new OESS::Entity(db => $db, entity_id => 124),
    service_key => "00000000-0000-0000-0000-000000000000"
);

my $pri3 = $selector3->select_interface($conn);
ok(defined $pri3 && $pri3->{interface_id} == 45901, "Got primary interface");

my $tri3 = $selector3->select_interface($conn);
ok(!defined $tri3, "Got no interface");


# BEGIN Verify if both primary and secondary in use, none is offered
#
my $vrf_ep_id4 = $db->execute_query("
insert into vrf_ep
(interface_id, tag, inner_tag, bandwidth, vrf_id, state, unit, mtu)
values (45901, 100, 100, 100, 1, 'active', 100, 9000)");

$db->execute_query("
    insert into cloud_connection_vrf_ep
    (vrf_ep_id, cloud_account_id, cloud_connection_id)
    values (?, '00000000-0000-0000-0000-000000000000', '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/CrossConnection-SiliconValleyTest/providers/Microsoft.Network/expressRouteCrossConnections/00000000-0000-0000-0000-000000000000')", [$vrf_ep_id4]);

my $selector4 = new OESS::Cloud::AzureInterfaceSelector(
    db => $db,
    entity => new OESS::Entity(db => $db, entity_id => 124),
    service_key => "00000000-0000-0000-0000-000000000000"
);

my $tri4 = $selector4->select_interface($conn);
ok(!defined $tri4, "Got no interface");
