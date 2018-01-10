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

my $mock = OESS::Mock->new;
$device->{jnx} = $mock;

$mock->new_sub(
    name => 'connected',
    result => 1
);

$mock->new_sub(
    name   => 'has_error',
    result => 0
);

$mock->new_sub(
    name => 'get_config',
    result => 1
);


my $result = undef;
my $err = undef;

$mock->new_sub(
    name => 'get_dom',
    result => XML::LibXML->load_xml(
        string => '<?xml version="1.0"?>
<rpc-reply xmlns="urn:ietf:params:xml:ns:netconf:base:1.0" xmlns:junos="http://xml.juniper.net/junos/15.1F6/junos" message-id="8">
<data>
<configuration xmlns="http://xml.juniper.net/xnm/1.1/xnm" changed-seconds="1510238032" changed-localtime="2017-11-09 14:33:52 UTC">
<version>15.1F6.9</version>
<interfaces>
<interface>
<name>ge-0/0/0</name>
<description>Management Interface</description>
<unit>
<name>0</name>
<family>
<inet>
<address>
<name>156.56.6.103/24</name>
</address>
</inet>
</family>
</unit>
</interface>
<interface>
<name>ge-0/0/1</name>
<description>R0 -&gt; R5</description>
<flexible-vlan-tagging/>
<mtu>9192</mtu>
<encapsulation>flexible-ethernet-services</encapsulation>
<unit>
<name>10</name>
<apply-groups>INTERFACE-BACKBONE</apply-groups>
<description>BACKBONE: R0-R5 | I2-LAB</description>
<vlan-id>10</vlan-id>
<family>
<inet>
<address>
<name>172.16.0.10/31</name>
</address>
</inet>
<inet6>
<address>
<name>fd01::1/64</name>
</address>
</inet6>
</family>
</unit>
</interface>
<interface>
<name>ge-0/0/2</name>
<description>[ae1] R0 - R1</description>
<gigether-options>
<ieee-802.3ad>
<bundle>ae1</bundle>
</ieee-802.3ad>
</gigether-options>
</interface>
<interface>
<name>ge-0/0/3</name>
<description>[ae1] R0 - R1</description>
<gigether-options>
<ieee-802.3ad>
<bundle>ae1</bundle>
</ieee-802.3ad>
</gigether-options>
</interface>
</interfaces>
</configuration>
</data>
</rpc-reply>')
);

$result = $device->unit_name_available('ge-0/0/1', 10);
ok($result == 0, 'Unit is not available.');

$result = $device->unit_name_available('ge-0/0/1', 20);
ok($result == 1, 'Unit is available.');

$err = $mock->sub_called(
    name  => 'get_dom',
    count => 2
);

ok(!defined $err, "unit_name_available called 3 times.");
warn "$err" if defined $err;
