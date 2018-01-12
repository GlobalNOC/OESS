use strict;
use warnings;

use Data::Dumper;

use OESS::Mock;
use OESS::MPLS::Device::Juniper::MX;
use XML::LibXML;

use Test::More tests => 3;


my $device = OESS::MPLS::Device::Juniper::MX->new(
    config        => '/etc/oess/database.xml',
    loopback_addr => '127.0.0.1',
    mgmt_addr     => '127.0.0.1',
    name          => 'vmx-r0.testlab.grnoc.iu.edu',
    node_id       => 1
);
$device->{'root_namespace'} = 'http://xml.juniper.net/junos/15.1F6/';


my $mock = OESS::Mock->new;
$device->{jnx} = $mock;

# Mock subroutines required for add_vlan but not under test.
$mock->new_sub(
    name => 'connected',
    result => 1
);

$mock->new_sub(
    name => 'has_error',
    result => 0
);

$mock->new_sub(
    name   => 'get_isis_adjacency_information',
    result => 1
);

$mock->new_sub(
    name   => 'get_dom',
    result => XML::LibXML->load_xml(string => '<?xml version="1.0"?>
<rpc-reply xmlns="urn:ietf:params:xml:ns:netconf:base:1.0" xmlns:junos="http://xml.juniper.net/junos/15.1F6/junos" message-id="5">
<isis-adjacency-information xmlns="http://xml.juniper.net/junos/15.1F6/junos-routing" style="detail">
<isis-adjacency>
<system-name>vmx-r3</system-name>
<interface-name>ae1.40</interface-name>
<level>2</level>
<adjacency-state>Up</adjacency-state>
<holdtime>25</holdtime>
<interface-priority>64</interface-priority>
<transition-count>1</transition-count>
<last-transition-time>
9w1d 04:21:06
</last-transition-time>
<circuit-type>2</circuit-type>
<adjacency-flag>Speaks: IP, IPv6</adjacency-flag>
<mac-address>0:5:86:5c:d9:c0</mac-address>
<adjacency-topologies>Unicast</adjacency-topologies>
<adjacency-restart-capable>yes</adjacency-restart-capable>
<adjacency-advertisement>advertise</adjacency-advertisement>
<lan-id>vmx-r2.03</lan-id>
<ip-address>172.16.0.19</ip-address>
<ipv6-address>fe80::205:8600:285c:d9c0</ipv6-address>
</isis-adjacency>
<isis-adjacency>
<system-name>vmx-r1</system-name>
<interface-name>ge-0/0/1.30</interface-name>
<level>2</level>
<adjacency-state>Up</adjacency-state>
<holdtime>20</holdtime>
<interface-priority>64</interface-priority>
<transition-count>1</transition-count>
<last-transition-time>
9w3d 21:16:34
</last-transition-time>
<circuit-type>2</circuit-type>
<adjacency-flag>Speaks: IP, IPv6</adjacency-flag>
<mac-address>2:6:a:e:ff:f5</mac-address>
<adjacency-topologies>Unicast</adjacency-topologies>
<adjacency-restart-capable>yes</adjacency-restart-capable>
<adjacency-advertisement>advertise</adjacency-advertisement>
<lan-id>vmx-r2.02</lan-id>
<ip-address>172.16.0.16</ip-address>
<ipv6-address>fe80::206:a00:1e0e:fff5</ipv6-address>
</isis-adjacency>
</isis-adjacency-information>
</rpc-reply>')
);

my $adjs = [
    {
        'interface_name' => 'ae1',
        'remote_system_name' => 'vmx-r3',
        'ip_address' => '172.16.0.19',
        'ipv6_address' => 'fe80::205:8600:285c:d9c0',
        'operational_state' => 'Up'
    },
    {
        'interface_name' => 'ge-0/0/1',
        'remote_system_name' => 'vmx-r1',
        'ip_address' => '172.16.0.16',
        'ipv6_address' => 'fe80::206:a00:1e0e:fff5',
        'operational_state' => 'Up'
    }
];

my $result = $device->get_isis_adjacencies();
my ($ok, $stack) = Test::Deep::cmp_details($result, $adjs);
ok($ok, "ISIS adjacencies discovered");

$mock->new_sub(
    name   => 'get_dom',
    result => XML::LibXML->load_xml(string => '<?xml version="1.0"?>
<rpc-reply xmlns="urn:ietf:params:xml:ns:netconf:base:1.0" xmlns:junos="http://xml.juniper.net/junos/15.1F6/junos" message-id="7">
    <commit-results>
        <load-success/>
        <rpc-error>
            <error-type>protocol</error-type>
            <error-tag>operation-failed</error-tag>
            <error-severity>error</error-severity>
            <source-daemon>dcd</source-daemon>
            <error-path>[edit interfaces ge-0/0/2]</error-path>
            <error-info>
            <bad-element>unit 2000</bad-element>
            </error-info>
            <error-message>logical unit is not allowed on aggregated links</error-message>
        </rpc-error>
        <rpc-error>
            <error-type>protocol</error-type>
            <error-tag>operation-failed</error-tag>
            <error-severity>error</error-severity>
            <error-message>configuration check-out failed</error-message>
        </rpc-error>
    </commit-results>
</rpc-reply>')
);

$result = $device->get_isis_adjacencies();
($ok, $stack) = Test::Deep::cmp_details($result, []);
ok($ok, "empty array returned when error message received.");

my $err = $mock->sub_called(
    name  => 'get_isis_adjacency_information',
    count => 2
);

ok(!defined $err, "get_isis_adjacency_information called 2 times.");
warn "$err" if defined $err;
