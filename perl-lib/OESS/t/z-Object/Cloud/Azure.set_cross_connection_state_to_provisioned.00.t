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
use Test::More tests => 17;

use OESSDatabaseTester;

use OESS::DB;
use OESS::Cloud::Azure;
use OESS::Cloud::AzurePeeringConfig;
use OESS::Config;
use OESS::Mock;
use HTTP::Response;
use HTTP::Request;
use JSON::XS;

OESSDatabaseTester::resetOESSDB(
    config => "$path/../../conf/database.xml",
    dbdump => "$path/../../conf/oess_known_state.sql"
);


my $db = new OESS::DB(config => "$path/../../conf/database.xml");

$db->execute_query(
    "update interface set cloud_interconnect_type='azure-express-route', cloud_interconnect_id=?, workgroup_id=? where interface_id=?",
    ["OessTest-SJC-TEST-00GMR-CIS-1-PRI-A", 21, 40871]
);
$db->execute_query(
    "update interface set cloud_interconnect_type='azure-express-route', cloud_interconnect_id=?, workgroup_id=? where interface_id=?",
    ["OessTest-SJC-TEST-00GMR-CIS-2-SEC-A", 21, 40891]
);
my $ni_id = $db->execute_query(
    "insert into node_instantiation (node_id,start_epoch,end_epoch,admin_state,dpid,openflow,mpls,controller) values (?,UNIX_TIMESTAMP(NOW()),-1,'active',987654567,0,1,'nso')",
    [5071]
);

my $vrf_id = $db->execute_query(
    "insert into vrf (name,description,workgroup_id,state,local_asn,created_by,last_modified_by) values (?,?,?,?,?,?,?)",
    ["demo","demo",21,"active",64789,1,1]
);

my $ep1_id = $db->execute_query(
    "insert into vrf_ep (vrf_id,interface_id,unit,tag,bandwidth,state,mtu) values (?,?,?,?,?,?,?)",
    [$vrf_id,40871,100,100,0,"active",1500]
);
my $ep2_id = $db->execute_query(
    "insert into vrf_ep (vrf_id,interface_id,unit,tag,bandwidth,state,mtu) values (?,?,?,?,?,?,?)",
    [$vrf_id,40891,100,100,0,"active",1500]
);

my $pr1_id = $db->execute_query(
    "insert into vrf_ep_peer (vrf_ep_id,ip_version,state,operational_state,local_ip,peer_ip,peer_asn) values (?,?,?,?,?,?,?)",
    [$ep1_id,"ipv4","active",1,"192.168.100.249/30","192.168.100.250/30",12076]
);
my $pr2_id = $db->execute_query(
    "insert into vrf_ep_peer (vrf_ep_id,ip_version,state,operational_state,local_ip,peer_ip,peer_asn) values (?,?,?,?,?,?,?)",
    [$ep2_id,"ipv4","active",1,"192.168.100.253/30","192.168.100.254/30",12076]
);

my $cld_ep1_id = $db->execute_query(
    "insert into cloud_connection_vrf_ep (vrf_ep_id,cloud_account_id,cloud_connection_id) values (?,?,?)",
    [$ep1_id,"11111111-1111-1111-1111-111111111111","/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/CrossConnection-SiliconValleyTest/providers/Microsoft.Network/expressRouteCrossConnections/11111111-1111-1111-1111-111111111111"]
);
my $cld_ep2_id = $db->execute_query(
    "insert into cloud_connection_vrf_ep (vrf_ep_id,cloud_account_id,cloud_connection_id) values (?,?,?)",
    [$ep2_id,"11111111-1111-1111-1111-111111111111","/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/CrossConnection-SiliconValleyTest/providers/Microsoft.Network/expressRouteCrossConnections/11111111-1111-1111-1111-111111111111"]
);


my $azure = new OESS::Cloud::Azure(
    config => "$path/../../conf/database.xml",
);
my $mock_http = new OESS::Mock();
my $interconnect_id1 = 'OessTest-SJC-TEST-00GMR-CIS-1-PRI-A';
my $interconnect_id2 = 'OessTest-SJC-TEST-00GMR-CIS-2-SEC-A';

$azure->{connections}->{$interconnect_id1}->{http} = $mock_http;
$azure->{connections}->{$interconnect_id2}->{http} = $mock_http;

my $resp = new HTTP::Response(200);
$resp->content("{}");
$mock_http->new_sub(
    name => 'request',
    result => $resp, # TODO make http response obj
);


my $circuit_id  = '00000000-1111-1111-1111-000000000000';
my $service_key = '11111111-1111-1111-1111-111111111111';
my $peering_location = 'CrossConnection-SiliconValleyTest';
my $region = 'us-east';
my $bandwidth = 1000;
my $vlan = 1234;
my $local_asn = 1337;
my $peering = undef;

# LAYER2

$azure->set_cross_connection_state_to_provisioned(
    interconnect_id  => $interconnect_id1,
    service_key      => $service_key,
    circuit_id       => $circuit_id,
    region           => $region,
    peering_location => $peering_location,
    bandwidth        => $bandwidth,
    vlan             => $vlan,
    local_asn        => $local_asn,
    peering          => $peering,
);

my $payload = $mock_http->sub_called_config(name => 'request');
my $req = $payload->{args}->[0];

my $json = decode_json($req->content);
warn Dumper($json);

ok($json->{properties}->{peeringLocation} eq $peering_location, "location");
ok($json->{properties}->{expressRouteCircuit}->{id} eq $circuit_id, "circuit_id");
ok($json->{properties}->{bandwidthInMbps} eq $bandwidth, "bandwidth");
ok($json->{properties}->{serviceProviderProvisioningState} eq 'Provisioned', "provisioned");
ok(!defined $json->{properties}->{peerings}, "peerings is undef");


# LAYER3

my $primary_prefix = '192.168.100.248/30';
my $secondary_prefix = '192.168.100.252/30';

# Used for testing OESS versions <= 2.0.14
# $peering = {
#     vlan             => $vlan,
#     local_asn        => $local_asn,
#     primary_prefix   => $primary_prefix,
#     secondary_prefix => $secondary_prefix,
# };

my $config = new OESS::Cloud::AzurePeeringConfig(db => $db);
$config->load($vrf_id);
$peering = $config->cross_connection_peering($service_key);

$azure->set_cross_connection_state_to_provisioned(
    interconnect_id  => $interconnect_id1,
    service_key      => $service_key,
    circuit_id       => $circuit_id,
    region           => $region,
    peering_location => $peering_location,
    bandwidth        => $bandwidth,
    vlan             => $vlan,
    local_asn        => $local_asn,
    peering          => $peering,
);

my $payload = $mock_http->sub_called_config(name => 'request');
my $req = $payload->{args}->[0];

my $json = decode_json($req->content);
warn Dumper($json);

ok($json->{properties}->{peeringLocation} eq $peering_location, "location");
ok($json->{properties}->{expressRouteCircuit}->{id} eq $circuit_id, "circuit_id");
ok($json->{properties}->{bandwidthInMbps} eq $bandwidth, "bandwidth");
ok($json->{properties}->{serviceProviderProvisioningState} eq 'Provisioned', "provisioned");
ok(@{$json->{properties}->{peerings}} == 1, "peerings count");
ok($json->{properties}->{peerings}->[0]->{name} eq 'AzurePrivatePeering', "peering name");
ok($json->{properties}->{peerings}->[0]->{properties}->{primaryPeerAddressPrefix} eq $primary_prefix, "peering pri prefix");
ok($json->{properties}->{peerings}->[0]->{properties}->{secondaryPeerAddressPrefix} eq $secondary_prefix, "peering sec prefix");
ok($json->{properties}->{peerings}->[0]->{properties}->{peerASN} eq $local_asn, "peering asn");
ok(!defined $json->{properties}->{peerings}->[0]->{properties}->{peeringType}, "peering type is undef");
ok($json->{properties}->{peerings}->[0]->{properties}->{state} eq 'Enabled', "peering state");
ok($json->{properties}->{peerings}->[0]->{properties}->{vlanId} eq $vlan, "peering vlan");
