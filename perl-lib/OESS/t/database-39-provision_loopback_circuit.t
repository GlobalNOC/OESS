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

use Test::More tests => 2;
use Test::Deep;
use OESS::Database;
use OESS::Circuit;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $workgroup_id = 11;

# bump le workgroup limits
&OESSDatabaseTester::workgroupLimits(
    db           => $db,
    workgroup_id => $workgroup_id,
    circuit_num  => 100
);

# Allow for interface modification
$db->add_acl(
    user_id       => 11,
    workgroup_id  => $workgroup_id,
    interface_id  => 391,
    allow_deny    => 'allow',
    eval_position => 40,
    vlan_start    => 1,
    vlan_end      => 4095,
    notes         => 'database-39'
);

my $res = $db->provision_circuit(
    'description' => "test_loopback",
    'bandwidth' => 1337,
    'provision_time' => -1,
    'remove_time' => -1,
    'links' => ['Link 171', 'Link 161', 'Link 31'],
    'backup_links' => [],
    'nodes' => ['Node 11', 'Node 11'], 
    'interfaces' => ['e15/1', 'e15/1'],
    'tags' => [2222,2223],
    'user_name' => 'user_251@foo.net',
    'workgroup_id' => $workgroup_id,
    'external_id' => undef
);
#verify circuit was successfully added
ok($res->{'success'}, "circuit successfully added");


# now create a OESS::Circuit object and verify the flowrules are what we'd expect for a loopback circuit
my $ckt = new OESS::Circuit( circuit_id => $res->{'circuit_id'}, db => $db );

my $endpoint_flows = $ckt->get_endpoint_flows( path => 'primary' );

my $correct_endpoint_flows = [
"OFFlowMod:
 DPID: 24389f8f00
 Priority: 32768
 Match: VLAN: 2222, IN PORT: 673
 Actions: SET VLAN ID: 101
          OUTPUT: 2\n",
"OFFlowMod:
 DPID: 24389f8f00
 Priority: 32768
 Match: VLAN: 100, IN PORT: 2
 Actions: SET VLAN ID: 2222
          OUTPUT: 673\n",
"OFFlowMod:
 DPID: 24389f8f00
 Priority: 32768
 Match: VLAN: 2223, IN PORT: 673
 Actions: SET VLAN ID: 100
          OUTPUT: 97\n",
"OFFlowMod:
 DPID: 24389f8f00
 Priority: 32768
 Match: VLAN: 100, IN PORT: 97
 Actions: SET VLAN ID: 2223
          OUTPUT: 673\n"
];

my $error = 0;
foreach my $flow (@$endpoint_flows){
    my $expected_flow = shift(@$correct_endpoint_flows);
    if($flow->to_human() ne $expected_flow){
        $error = 1;
        print "GENERATED FLOW :\n\n".$flow->to_human()."\n\n";
        print " DOES NOT MATCH\n"; 
        print "EXPECTED FLOW  :\n\n".$expected_flow."\n"; 
        last;
    }
}

ok(!$error, "endpoint flows are correct!");
