use strict;
use warnings;

use Data::Dumper;

use OESS::Mock;
use OESS::MPLS::Device::Juniper::MX;
use XML::LibXML;

use Test::More tests => 6;


my $device = OESS::MPLS::Device::Juniper::MX->new(
    config        => '/etc/oess/database.xml',
    loopback_addr => '127.0.0.1',
    mgmt_addr     => '127.0.0.1',
    name          => 'vmx-r0.testlab.grnoc.iu.edu',
    node_id       => 1
);

my $mock = OESS::Mock->new;
$device->{jnx} = $mock;

$mock->new_sub(
    name   => 'has_error',
    result => 0
);

$mock->new_sub(
    name => 'get_dom',
    result => XML::LibXML->load_xml(
        string => '<?xml version="1.0"?>
<rpc-reply xmlns="urn:ietf:params:xml:ns:netconf:base:1.0" xmlns:junos="http://xml.juniper.net/junos/15.1F6/junos" message-id="1">
<system-information>
<hardware-model>vmx</hardware-model>
<os-name>junos</os-name>
<os-version>15.1F6.9</os-version>
<serial-number>VM59C5531A32</serial-number>
<host-name>vmx-r0</host-name>
</system-information>
</rpc-reply>'
    )
);


$mock->new_sub(
    name => 'get_dom',
    result => XML::LibXML->load_xml(
        string => '<?xml version="1.0"?>
<rpc-reply xmlns="urn:ietf:params:xml:ns:netconf:base:1.0" xmlns:junos="http://xml.juniper.net/junos/15.1F6/junos" message-id="4">
<system-information>
<hardware-model>vmx</hardware-model>
<os-name>junos</os-name>
<os-version>15.1F6.9</os-version>
<serial-number>VM59C5531A32</serial-number>
<host-name>vmx-r0</host-name>
</system-information>
<interface-information xmlns="http://xml.juniper.net/junos/15.1F6/junos-interface" junos:style="normal">
<physical-interface>
<name>lo0</name>
<admin-status junos:format="Enabled">up</admin-status>
<oper-status>up</oper-status>
<local-index>6</local-index>
<snmp-index>6</snmp-index>
<if-type>Loopback</if-type>
<mtu>Unlimited</mtu>
<if-device-flags>
<ifdf-present/>
<ifdf-running/>
<ifdf-loopback/>
</if-device-flags>
<ifd-specific-config-flags>
<internal-flags>0x200</internal-flags>
</ifd-specific-config-flags>
<if-config-flags>
<iff-snmp-traps/>
</if-config-flags>
<if-media-flags>
<ifmf-none/>
</if-media-flags>
<interface-flapped junos:seconds="0">Never</interface-flapped>
<traffic-statistics junos:style="brief">
<input-packets>1801566</input-packets>
<output-packets>1801566</output-packets>
</traffic-statistics>
<logical-interface>
<name>lo0.0</name>
<local-index>347</local-index>
<snmp-index>16</snmp-index>
<if-config-flags>
<iff-snmp-traps/>
</if-config-flags>
<encapsulation>Unspecified</encapsulation>
<policer-overhead>
</policer-overhead>
<traffic-statistics junos:style="brief">
<input-packets>34660</input-packets>
<output-packets>34660</output-packets>
</traffic-statistics>
<filter-information>
</filter-information>
<address-family>
<address-family-name>inet</address-family-name>
<mtu>Unlimited</mtu>
<address-family-flags>
<ifff-sendbcast-pkt-to-re/>
<internal-flags>0x0</internal-flags>
</address-family-flags>
<interface-address>
<ifa-flags>
<ifaf-preferred/>
<ifaf-current-default/>
<ifaf-current-primary/>
</ifa-flags>
<ifa-local>172.16.0.1</ifa-local>
</interface-address>
</address-family>
<address-family>
<address-family-name>iso</address-family-name>
<mtu>Unlimited</mtu>
<address-family-flags>
<internal-flags>0x0</internal-flags>
</address-family-flags>
<interface-address>
<ifa-flags>
<ifaf-current-default/>
<ifaf-current-primary/>
</ifa-flags>
<ifa-local>49.0000.1720.1600.0001</ifa-local>
</interface-address>
</address-family>
<address-family>
<address-family-name>inet6</address-family-name>
<mtu>Unlimited</mtu>
<max-local-cache>0</max-local-cache>
<new-hold-limit>0</new-hold-limit>
<intf-curr-cnt>0</intf-curr-cnt>
<intf-unresolved-cnt>0</intf-unresolved-cnt>
<intf-dropcnt>0</intf-dropcnt>
<address-family-flags>
<internal-flags>0x0</internal-flags>
</address-family-flags>
<interface-address>
<ifa-flags>
<ifaf-current-default/>
<ifaf-current-primary/>
</ifa-flags>
<ifa-local>fc00::1</ifa-local>
<interface-address>
<in6-addr-flags>
<ifaf-none/>
</in6-addr-flags>
</interface-address>
</interface-address>
<interface-address>
<ifa-flags>
<internal-flags>0x800</internal-flags>
</ifa-flags>
<ifa-local>fe80::a00:dd0f:fcc1:de1e</ifa-local>
<interface-address>
<in6-addr-flags>
<ifaf-none/>
</in6-addr-flags>
</interface-address>
</interface-address>
</address-family>
</logical-interface>
<logical-interface>
<name>lo0.16384</name>
<local-index>320</local-index>
<snmp-index>21</snmp-index>
<if-config-flags>
<iff-snmp-traps/>
</if-config-flags>
<encapsulation>Unspecified</encapsulation>
<policer-overhead>
</policer-overhead>
<traffic-statistics junos:style="brief">
<input-packets>2437</input-packets>
<output-packets>2437</output-packets>
</traffic-statistics>
<filter-information>
</filter-information>
<address-family>
<address-family-name>inet</address-family-name>
<mtu>Unlimited</mtu>
<address-family-flags>
<internal-flags>0x0</internal-flags>
</address-family-flags>
<interface-address heading="Addresses">
<ifa-local>127.0.0.1</ifa-local>
</interface-address>
</address-family>
</logical-interface>
<logical-interface>
<name>lo0.16385</name>
<local-index>321</local-index>
<snmp-index>22</snmp-index>
<if-config-flags>
<iff-snmp-traps/>
</if-config-flags>
<encapsulation>Unspecified</encapsulation>
<policer-overhead>
</policer-overhead>
<traffic-statistics junos:style="brief">
<input-packets>1764450</input-packets>
<output-packets>1764450</output-packets>
</traffic-statistics>
<filter-information>
</filter-information>
<address-family>
<address-family-name>inet</address-family-name>
<mtu>Unlimited</mtu>
<address-family-flags>
<internal-flags>0x0</internal-flags>
</address-family-flags>
</address-family>
</logical-interface>
</physical-interface>
</interface-information>
</rpc-reply>')
);

my $result = $device->get_system_information();

my $err = $mock->sub_called(
name  => 'get_system_information',
count => 1
);

ok(!defined $err, "get_system_information called 1 time.");
warn "$err" if defined $err;

ok($result->{os_name} eq 'junos', 'Got expected os');
ok($result->{version} eq '15.1F6.9', 'Got expected version');
ok($result->{host_name} eq 'vmx-r0', 'Got expected host_name');
ok($result->{model} eq 'vmx', 'Got expected model');
ok($result->{loopback_addr} eq '172.16.0.1', 'Got expected loopback_addr');
