#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;
use Test::More tests => 1;

use XML::LibXML;

use OESS::MPLS::Device::Juniper::MX;


# Purpose:
#
# Validate correct generation of L2VPLS L2Connection template.


my $exp_xml = '<configuration>
  <groups operation="delete"><name>OESS</name></groups>
  <groups>
    <name>OESS</name>
    <interfaces>
      <interface>
        <name>ge-0/0/1</name>
        <unit>
          <name>2004</name>
          <description>OESS-L2VPLS-3012</description>
          <encapsulation>vlan-vpls</encapsulation>
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
          <description>OESS-L2VPLS-3012</description>
          <encapsulation>vlan-vpls</encapsulation>
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
        <name>OESS-L2VPLS-3012</name>
        <instance-type>vpls</instance-type>
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
          <vpls>
            <site-range>65534</site-range>
            <no-tunnel-services/>
            <site>
              <name>vmx-r0.testlab.grnoc.iu.edu-3012</name>
              <site-identifier>1</site-identifier>
            </site>
          </vpls>
        </protocols>
      </instance>
    </routing-instances>
  </groups>
  <apply-groups>OESS</apply-groups>
</configuration>';

my $device = OESS::MPLS::Device::Juniper::MX->new(
    config => '/etc/oess/database.xml',
    loopback_addr => '127.0.0.1',
    mgmt_addr => '127.0.0.1',
    name => 'vmx-r0.testlab.grnoc.iu.edu',
    node_id => 1
);
my $conf = $device->xml_configuration(
    [{
        name => 'circuit',
        endpoints => [
            {
                interface => 'ge-0/0/1',
                unit => 2004,
                tag => 2004,
                inner_tag => 30, # CHECK: QinQ
                bandwidth => 50, # CHECK: class-of-service added
                mtu => 9000      # CHECK: mtu omitted
            },
            {
                interface => 'ge-0/0/2',
                unit => 2004,
                tag => 2004,
                bandwidth => 0,  # CHECK: class-of-service omitted
                mtu => 8080      # CHECK: mtu omitted
            }
        ],
        paths => [],
        circuit_id => 3012,
        site_id => 1,
        state => 'active',
        ckt_type => 'L2VPLS'
    }],
    [],
    '<groups operation="delete"><name>OESS</name></groups>'
);

# Load expected and generated XML and convert to string minus
# whitespace for easy comparision.
my $exml = XML::LibXML->load_xml(string => $exp_xml, {no_blanks => 1});
my $gxml = XML::LibXML->load_xml(string => $conf, {no_blanks => 1});

my $e = $exml->toString;
my $g = $gxml->toString;

ok($e eq $g, 'Got expected XMl');
if ($e ne $g) {
    warn Dumper($e);
    warn Dumper($g);
}
