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
use Test::More tests => 6;

use OESSDatabaseTester;

use OESS::DB;
use OESS::Cloud::AzureStub;
use OESS::Cloud::AzureSyncer;
use OESS::Config;
use OESS::NSO::FWDCTL;

OESSDatabaseTester::resetOESSDB(
    config => "$path/../../conf/database.xml",
    dbdump => "$path/../../conf/oess_known_state.sql"
);


# Setup azure endpoints
my $db = new OESS::DB(config => "$path/../../conf/database.xml");
my $ok;

$ok = $db->execute_query(
    "update interface set cloud_interconnect_type='azure-express-route', cloud_interconnect_id=?, workgroup_id=? where interface_id=?",
    ["OessTest-SJC-TEST-00GMR-CIS-1-PRI-A", 21, 40871]
);
warn $db->get_error if !$ok;
$ok = $db->execute_query(
    "update interface set cloud_interconnect_type='azure-express-route', cloud_interconnect_id=?, workgroup_id=? where interface_id=?",
    ["OessTest-SJC-TEST-00GMR-CIS-2-SEC-A", 21, 40891]
);
warn $db->get_error if !$ok;
my $ni_id = $db->execute_query(
    "insert into node_instantiation (node_id,start_epoch,end_epoch,admin_state,dpid,openflow,mpls,controller) values (?,UNIX_TIMESTAMP(NOW()),-1,'active','987654567',0,1,'nso')",
    [5071]
);
warn $db->get_error if !defined $ni_id;

my $vrf_id = $db->execute_query(
    "insert into vrf (name,description,workgroup_id,state,local_asn,created_by,last_modified_by) values (?,?,?,?,?,?,?)",
    ["demo","demo",21,"active",64789,1,1]
);
warn $db->get_error if !$vrf_id;

my $ep1_id = $db->execute_query(
    "insert into vrf_ep (vrf_id,interface_id,unit,tag,bandwidth,state,mtu) values (?,?,?,?,?,?,?)",
    [$vrf_id,40871,100,100,0,"active",1500]
);
warn $db->get_error if !$ep1_id;
my $ep2_id = $db->execute_query(
    "insert into vrf_ep (vrf_id,interface_id,unit,tag,bandwidth,state,mtu) values (?,?,?,?,?,?,?)",
    [$vrf_id,40891,100,100,0,"active",1500]
);
warn $db->get_error if !$ep2_id;

my $cld_ep1_id = $db->execute_query(
    "insert into cloud_connection_vrf_ep (vrf_ep_id,cloud_account_id,cloud_connection_id) values (?,?,?)",
    [$ep1_id,"11111111-1111-1111-1111-111111111111","/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/CrossConnection-SiliconValleyTest/providers/Microsoft.Network/expressRouteCrossConnections/11111111-1111-1111-1111-111111111111"]
);
warn $db->get_error if !$cld_ep1_id;
my $cld_ep2_id = $db->execute_query(
    "insert into cloud_connection_vrf_ep (vrf_ep_id,cloud_account_id,cloud_connection_id) values (?,?,?)",
    [$ep2_id,"11111111-1111-1111-1111-111111111111","/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/CrossConnection-SiliconValleyTest/providers/Microsoft.Network/expressRouteCrossConnections/11111111-1111-1111-1111-111111111111"]
);
warn $db->get_error if !$cld_ep2_id;

my $pr1_id = $db->execute_query(
    "insert into vrf_ep_peer (vrf_ep_id,ip_version,state,operational_state,local_ip,peer_ip,peer_asn) values (?,?,?,?,?,?,?)",
    [$ep1_id,"ipv4","active",1,"192.168.100.249/30","192.168.100.250/30",12076]
);
warn $db->get_error if !$pr1_id;
my $pr2_id = $db->execute_query(
    "insert into vrf_ep_peer (vrf_ep_id,ip_version,state,operational_state,local_ip,peer_ip,peer_asn) values (?,?,?,?,?,?,?)",
    [$ep2_id,"ipv4","active",1,"192.168.100.253/30","192.168.100.254/30",12076]
);
warn $db->get_error if !$pr2_id;


my $azure = new OESS::Cloud::AzureSyncer(
    config => new OESS::Config(config_filename => "$path/../../conf/database.xml"),
    azure  => new OESS::Cloud::AzureStub(config => "$path/../../conf/database.xml"),
);

my ($endpoints, $err) = $azure->fetch_azure_endpoints_from_oess();
ok(@$endpoints == 2, "Fetched expected number of endpoints.");
warn $err if defined $err;

my ($conns, $err2) = $azure->fetch_cross_connections_from_azure();
warn Dumper($conns);
warn Dumper($err2);
warn Dumper($azure);
ok(keys %$conns == 1, "Fetched expected number of connections.");
warn $err2 if defined $err2;

my $ep1 = $endpoints->[0];
my $conn1 = $conns->{$ep1->cloud_connection_id};

my $subnets1 = $azure->get_peering_addresses_from_azure($conn1, $ep1->cloud_interconnect_id);
ok($subnets1->[0]->{local_ip} eq "192.168.100.249/30", "Got expected local_ip");
ok($subnets1->[0]->{remote_ip} eq "192.168.100.250/30", "Got expected remote_ip");

my $ep2 = $endpoints->[1];
my $conn2 = $conns->{$ep1->cloud_connection_id};

my $subnets2 = $azure->get_peering_addresses_from_azure($conn2, $ep2->cloud_interconnect_id);
ok($subnets2->[0]->{local_ip} eq "192.168.100.253/30", "Got expected local_ip");
ok($subnets2->[0]->{remote_ip} eq "192.168.100.254/30", "Got expected remote_ip");

