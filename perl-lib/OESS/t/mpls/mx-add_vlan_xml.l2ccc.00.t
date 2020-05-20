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
          <description>OESS-L2CCC-3012</description>
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
          <description>OESS-L2CCC-3012</description>
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

    <protocols>
      <mpls>
        <label-switched-path>
          <name>OESS-L2CCC-100-200-LSP-3012</name>
          <apply-groups>L2CCC-LSP-ATTRIBUTES</apply-groups>
          <to>192.168.1.200</to>
          <primary>
            <name>OESS-L2CCC-100-200-LSP-3012-PRIMARY</name>
          </primary>
          <secondary>
            <name>OESS-L2CCC-100-200-LSP-3012-TERTIARY</name>
            <standby/>
          </secondary>
        </label-switched-path>
        <path>
          <name>OESS-L2CCC-100-200-LSP-3012-PRIMARY</name>
          <path-list>
            <name>192.186.1.150</name>
            <strict/>
          </path-list>
          <path-list>
            <name>192.168.1.200</name>
            <strict/>
          </path-list>
        </path>
        <path>
          <name>OESS-L2CCC-100-200-LSP-3012-TERTIARY</name>
        </path>
      </mpls>
      <connections>
        <remote-interface-switch>
          <name>OESS-L2CCC-3012</name>
          <interface>ge-0/0/1.2004</interface>
          <interface>ge-0/0/2.2004</interface>
          <transmit-lsp>OESS-L2CCC-100-200-LSP-3012</transmit-lsp>
          <receive-lsp>OESS-L2CCC-200-100-LSP-3012</receive-lsp>
        </remote-interface-switch>
      </connections>
    </protocols>
  </groups>
</configuration>';

my $device = OESS::MPLS::Device::Juniper::MX->new(
    config => '/etc/oess/database.xml',
    loopback_addr => '192.168.1.150',
    mgmt_addr => '127.0.0.1',
    name => 'vmx-r0.testlab.grnoc.iu.edu',
    node_id => 1
);
$device->{jnx} = { conn_obj => 1 }; # Fake being connected. :)

my $conf = $device->add_vlan_xml({
    name => 'circuit',
    endpoints => [
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
    paths => [
        {
            type => 'primary',
            details => {
                node_a => { node_id => 100, node_loopback => '192.168.1.150' },
                node_z => { node_id => 200, node_loopback => '192.168.1.200' },
                hops => [
                    '192.186.1.150',
                    '192.168.1.200'
                ]
            },
            mpls_type => 'strict',
            path => [
                '192.186.1.150',
                '192.168.1.200'
            ]
        },
        {
            name => 'tertiary',
            mpls_type => 'loose',
            details => {
                node_a => { node_id => 100, node_loopback => '192.168.1.150' },
                node_z => { node_id => 200, node_loopback => '192.168.1.200' },
                hops => [
                    '192.186.1.150',
                    '192.168.1.200'
                ]
            }
        }
    ],
    circuit_id => 3012,
    site_id => 1,
    state => 'active',
    dest => '192.168.1.200',
    a_side => 100,
    ckt_type => 'L2CCC'
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
