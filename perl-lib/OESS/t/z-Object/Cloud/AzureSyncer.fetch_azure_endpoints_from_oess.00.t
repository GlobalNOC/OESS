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
use Test::More tests => 1;

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


my $azure = new OESS::Cloud::AzureSyncer(
    config => new OESS::Config(config_filename => "$path/../../conf/database.xml"),
    azure  => new OESS::Cloud::AzureStub(config => "$path/../../conf/database.xml"),
);

my ($eps, $err) = $azure->fetch_azure_endpoints_from_oess();
ok(@$eps == 2, "Fetched expected number of endpoints.");
