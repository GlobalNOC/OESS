#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;
use Test::More tests => 1;

use XML::LibXML;

use OESS::MPLS::Device::Juniper::MX;


# Purpose:
#
# Validate correct generation of add L2Connection template.


my $exp_xml = '<configuration>
  <groups>
    <name>OESS</name>
    <interfaces>
      <interface>
        <name>ge-0/0/1</name>
        <unit>
          <name>2004</name>
          <description>OESS-L2VPN-3012</description>
          <encapsulation>vlan-ccc</encapsulation>
          <vlan-tags>
            <outer>2004</outer>
            <inner>30</inner>
          </vlan-tags>
          <output-vlan-map>
            <swap/>
          </output-vlan-map>
        </unit>
      </interface>
      <interface>
        <name>ge-0/0/2</name>
        <unit>
          <name>2004</name>
          <description>OESS-L2VPN-3012</description>
          <encapsulation>vlan-ccc</encapsulation>
          <vlan-id>2004</vlan-id>
          <output-vlan-map>
            <swap/>
          </output-vlan-map>
        </unit>
      </interface>
    </interfaces>

    <class-of-service>
      <interfaces>
        <interface>
          <name>ge-0/0/1</name>
          <unit>
            <name>2004</name>
            <shaping-rate><rate>50m</rate></shaping-rate>
          </unit>
        </interface>
      </interfaces>
    </class-of-service>

  <routing-instances>
    <instance>
      <name>OESS-L2VPN-3012</name>
      <instance-type>l2vpn</instance-type>
      <interface>
        <name>ge-0/0/1.2004</name>
      </interface>
      <interface>
        <name>ge-0/0/2.2004</name>
      </interface>
      <route-distinguisher>
        <rd-type>11537:3012</rd-type>
      </route-distinguisher>
      <vrf-target>
        <community>target:11537:3012</community>
      </vrf-target>
      <protocols>
      <l2vpn>
        <encapsulation-type>ethernet-vlan</encapsulation-type>
        <site>
          <name>vmx-r0.testlab.grnoc.iu.edu-3012</name>
          <site-identifier>1</site-identifier>
          <interface>
            <name>ge-0/0/1.2004</name>
          </interface>
          <interface>
            <name>ge-0/0/2.2004</name>
          </interface>
        </site>
      </l2vpn>
      </protocols>
    </instance>
  </routing-instances>
  </groups>
</configuration>';

my $device = OESS::MPLS::Device::Juniper::MX->new(
    config => '/etc/oess/database.xml',
    loopback_addr => '127.0.0.1',
    mgmt_addr => '127.0.0.1',
    name => 'vmx-r0.testlab.grnoc.iu.edu',
    node_id => 1
);
$device->{jnx} = { conn_obj => 1 }; # Fake being connected. :)

my $conf = $device->add_vlan_xml({
    circuit_name => 'circuit',
    interfaces => [
        {
            interface => 'ge-0/0/1',
            unit => 2004,
            tag => 2004,
            inner_tag => 30, # CHECK: QinQ
            bandwidth => 50, # CHECK: class-of-service added
            mtu => 9000      # CHECK: family > ccc > mtu added
        },
        {
            interface => 'ge-0/0/2',
            unit => 2004,
            tag => 2004,
            bandwidth => 0,  # CHECK: class-of-service omitted
            mtu => 0         # CHECK: family > ccc > mtu omitted
        }
    ],
    paths => [],
    circuit_id => 3012,
    site_id => 1,
    state => 'active',
    dest => '192.168.1.200',
    a_side => 100,
    ckt_type => 'L2VPN'
});

# Load expected and generated XML and convert to string minus
# whitespace for easy comparision.
my $exml = XML::LibXML->load_xml(string => $exp_xml, {no_blanks => 1});
my $gxml = XML::LibXML->load_xml(string => $conf, {no_blanks => 1});

my $e = $exml->toString;
my $g = $gxml->toString;

ok($e eq $g, 'Got expected XMl');
if ($e ne $g) {
    warn 'Expected: ' . Dumper($e);
    warn 'Generated: ' . Dumper($g);
}
