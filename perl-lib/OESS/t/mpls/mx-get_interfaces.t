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
    name   => 'get_interface_information',
    result => 1
);

$mock->new_sub(
    name   => 'get_dom',
    result => XML::LibXML->load_xml(string => '<?xml version="1.0"?>
<rpc-reply xmlns="urn:ietf:params:xml:ns:netconf:base:1.0" xmlns:junos="http://xml.juniper.net/junos/15.1F6/junos" message-id="8">
<interface-information xmlns="http://xml.juniper.net/junos/15.1F6/junos-interface" style="normal">
<physical-interface>
<name>
ge-0/0/0
</name>
<admin-status format="Enabled">
up
</admin-status>
<oper-status>
up
</oper-status>
<local-index>
139
</local-index>
<snmp-index>
517
</snmp-index>
<description>
Management Interface
</description>
<link-level-type>
Ethernet
</link-level-type>
<mtu>
1514
</mtu>
<sonet-mode>
LAN-PHY
</sonet-mode>
<mru>
1522
</mru>
<source-filtering>
disabled
</source-filtering>
<speed>
1000mbps
</speed>
<bpdu-error>
none
</bpdu-error>
<l2pt-error>
none
</l2pt-error>
<loopback>
disabled
</loopback>
<if-flow-control>
enabled
</if-flow-control>
<pad-to-minimum-frame-size>
Disabled
</pad-to-minimum-frame-size>
<if-device-flags>
<ifdf-present/>
<ifdf-running/>
</if-device-flags>
<ifd-specific-config-flags>
<internal-flags>
0x200
</internal-flags>
</ifd-specific-config-flags>
<if-config-flags>
<iff-snmp-traps/>
<internal-flags>
0x4000
</internal-flags>
</if-config-flags>
<if-media-flags>
<ifmf-none/>
</if-media-flags>
<physical-interface-cos-information>
<physical-interface-cos-hw-max-queues>
8
</physical-interface-cos-hw-max-queues>
<physical-interface-cos-use-max-queues>
8
</physical-interface-cos-use-max-queues>
</physical-interface-cos-information>
<current-physical-address>
02:06:0a:0e:ff:f0
</current-physical-address>
<hardware-physical-address>
02:06:0a:0e:ff:f0
</hardware-physical-address>
<interface-flapped seconds="9332371">
2017-09-26 20:57:01 UTC (15w3d 00:19 ago)
</interface-flapped>
<traffic-statistics style="brief">
<input-bps>
9200
</input-bps>
<input-pps>
10
</input-pps>
<output-bps>
92864
</output-bps>
<output-pps>
22
</output-pps>
</traffic-statistics>
<active-alarms>
<interface-alarms>
<alarm-not-present/>
</interface-alarms>
</active-alarms>
<active-defects>
<interface-alarms>
<alarm-not-present/>
</interface-alarms>
</active-defects>
<interface-transmit-statistics>
Disabled
</interface-transmit-statistics>
<logical-interface>
<name>
ge-0/0/0.0
</name>
<local-index>
332
</local-index>
<snmp-index>
527
</snmp-index>
<if-config-flags>
<iff-up/>
<iff-snmp-traps/>
<internal-flags>
0x4004000
</internal-flags>
</if-config-flags>
<encapsulation>
ENET2
</encapsulation>
<policer-overhead>
</policer-overhead>
<traffic-statistics style="brief">
<input-packets>
139822087
</input-packets>
<output-packets>
232467134
</output-packets>
</traffic-statistics>
<filter-information>
</filter-information>
<address-family>
<address-family-name>
inet
</address-family-name>
<mtu>
1500
</mtu>
<address-family-flags>
<ifff-is-primary/>
<ifff-sendbcast-pkt-to-re/>
<internal-flags>
0x0
</internal-flags>
</address-family-flags>
<interface-address>
<ifa-flags>
<ifaf-current-preferred/>
<ifaf-current-primary/>
</ifa-flags>
<ifa-destination>
156.56.6/24
</ifa-destination>
<ifa-local>
156.56.6.103
</ifa-local>
<ifa-broadcast>
156.56.6.255
</ifa-broadcast>
</interface-address>
</address-family>
<address-family>
<address-family-name>
multiservice
</address-family-name>
<mtu>
Unlimited
</mtu>
<address-family-flags>
<ifff-is-primary/>
<internal-flags>
0x0
</internal-flags>
</address-family-flags>
</address-family>
</logical-interface>
</physical-interface>
</interface-information>
</rpc-reply>')
);

my $ints = [{
    'addresses' => [
        '156.56.6.103'
    ],
    'name' => 'ge-0/0/0',
    'description' => 'Management Interface',
    'admin_state' => 'up',
    'operational_state' => 'up'
}];

my $result = $device->get_interfaces();
my ($ok, $stack) = Test::Deep::cmp_details($result, $ints);
ok($ok, "Interfaces discovered");

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

$result = $device->get_interfaces();
($ok, $stack) = Test::Deep::cmp_details($result, []);
ok($ok, "empty array returned when error message received.");


my $err = $mock->sub_called(
    name  => 'get_interface_information',
    count => 2
);

ok(!defined $err, "get_interface_information called 2 times.");
warn "$err" if defined $err;
