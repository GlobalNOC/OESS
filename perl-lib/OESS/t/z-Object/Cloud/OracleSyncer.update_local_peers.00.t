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
use Test::More tests => 14;

use OESSDatabaseTester;

use OESS::DB;
use OESS::Cloud::OracleStub;
use OESS::Cloud::OracleSyncer;
use OESS::Config;
use OESS::NSO::FWDCTL;

OESSDatabaseTester::resetOESSDB(
    config => "$path/../../conf/database.xml",
    dbdump => "$path/../../conf/oess_known_state.sql"
);


# Setup azure endpoints
my $db = new OESS::DB(config => "$path/../../conf/database.xml");
$db->execute_query(
    "update interface set cloud_interconnect_type='oracle-fast-connect', cloud_interconnect_id=?, workgroup_id=? where interface_id=?",
    ["CrossConnect1", 21, 40871]
);
$db->execute_query(
    "update interface set cloud_interconnect_type='oracle-fast-connect', cloud_interconnect_id=?, workgroup_id=? where interface_id=?",
    ["CrossConnect11", 21, 40891]
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

my $cld_ep1_id = $db->execute_query(
    "insert into cloud_connection_vrf_ep (vrf_ep_id,cloud_account_id,cloud_connection_id) values (?,?,?)",
    [$ep1_id,"UniqueVirtualCircuitId123","UniqueVirtualCircuitId123"]
);
my $cld_ep2_id = $db->execute_query(
    "insert into cloud_connection_vrf_ep (vrf_ep_id,cloud_account_id,cloud_connection_id) values (?,?,?)",
    [$ep2_id,"UniqueVirtualCircuitId123","UniqueVirtualCircuitId123"]
);

my $pr1_id = $db->execute_query(
    "insert into vrf_ep_peer (vrf_ep_id,ip_version,state,operational_state,local_ip,peer_ip,peer_asn) values (?,?,?,?,?,?,?)",
    [$ep1_id,"ipv4","active",1,"192.168.100.2/31","192.168.100.3/31",12076]
);
my $pr2_id = $db->execute_query(
    "insert into vrf_ep_peer (vrf_ep_id,ip_version,state,operational_state,local_ip,peer_ip,peer_asn) values (?,?,?,?,?,?,?)",
    [$ep2_id,"ipv4","active",1,"192.168.100.4/31","192.168.100.5/31",12076]
);


my $oracle = new OESS::Cloud::OracleSyncer(
    config => new OESS::Config(config_filename => "$path/../../conf/database.xml"),
    oracle => new OESS::Cloud::OracleStub(config => "$path/../../conf/database.xml", interconnect_id => 'ocid1.crossconnectgroup.oc1.iad.0000'),
);

my ($endpoints, $err) = $oracle->fetch_oracle_endpoints_from_oess();
ok(@$endpoints == 2, "Fetched expected number of endpoints.");

my ($conns, $err) = $oracle->fetch_virtual_circuits_from_oracle();
ok(keys %$conns == 3, "Fetched expected number of virtual circuits.");


my $conn = $conns->{"UniqueVirtualCircuitId123"};
my $eps  = {};

$eps->{$endpoints->[0]->cloud_interconnect_id} = $endpoints->[0];
$eps->{$endpoints->[1]->cloud_interconnect_id} = $endpoints->[1];

foreach my $cc (@{$conn->{crossConnectMappings}}) {
    my $endpoint     = $eps->{$cc->{crossConnectOrCrossConnectGroupId}};
    my $remote_peers = $oracle->get_peering_addresses_from_oracle($conn, $cc->{crossConnectOrCrossConnectGroupId});

    my $err1 = $oracle->update_local_peers(
        endpoint     => $endpoint,
        remote_peers => $remote_peers
    );
    ok(!defined $err1, "No error while updating local peers.");
}


my ($endpoints2, $err2) = $oracle->fetch_oracle_endpoints_from_oess();
ok(@$endpoints2 == 2, "Fetched expected number of endpoints.");

ok($endpoints2->[0]->peers->[0]->{ip_version} eq 'ipv4', "Got expected ip version");
ok($endpoints2->[0]->peers->[0]->{local_ip} eq '10.0.0.18/31', "Got expected local ip");
ok($endpoints2->[0]->peers->[0]->{peer_ip} eq '10.0.0.19/31', "Got expected peer ip");

ok($endpoints2->[1]->peers->[0]->{ip_version} eq 'ipv4', "Got expected ip version");
ok($endpoints2->[1]->peers->[0]->{local_ip} eq '10.0.0.20/31', "Got expected local ip");
ok($endpoints2->[1]->peers->[0]->{peer_ip} eq '10.0.0.21/31', "Got expected peer ip");

ok($endpoints2->[1]->peers->[1]->{ip_version} eq 'ipv6', "Got expected ip version");
ok($endpoints2->[1]->peers->[1]->{local_ip} eq 'fd99:8e08:a70d:c444::2/127', "Got expected local ip");
ok($endpoints2->[1]->peers->[1]->{peer_ip} eq 'fd99:8e08:a70d:c444::3/127', "Got expected peer ip");
