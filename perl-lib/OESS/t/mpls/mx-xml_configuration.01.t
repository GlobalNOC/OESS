#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;

use OESS::Mock;
use OESS::MPLS::Device::Juniper::MX;

use Test::More tests => 1;

# Purpose:
#
# Verify that class-of-service is added to layer2 connections when
# non-zero bandwidth is defined on an Endpoint.

my $device = OESS::MPLS::Device::Juniper::MX->new(
    config => '/etc/oess/database.xml',
    loopback_addr => '127.0.0.1',
    mgmt_addr => '127.0.0.1',
    name => 'vmx-r0.testlab.grnoc.iu.edu',
    node_id => 1
);

my $exp_xml = '<configuration><groups operation="delete"><name>OESS</name></groups><groups><name>OESS</name>
  <interfaces>
    
    <interface>
      <name>ge-0/0/1</name>
      <unit>
        <name>2004</name>
        <description>OESS-L2VPLS-3012</description>
        <family>
          <inet><mtu>9000</mtu></inet>
          <inet6><mtu>9000</mtu></inet6>
        </family>
        <encapsulation>vlan-vpls</encapsulation>
        
        <vlan-id>2004</vlan-id>
        
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
        <family>
          <inet><mtu>8080</mtu></inet>
          <inet6><mtu>8080</mtu></inet6>
        </family>
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

</groups><apply-groups>OESS</apply-groups></configuration>';

my $conf = $device->xml_configuration(
    [{
        circuit_name => 'circuit',
        interfaces => [
            {
                interface => 'ge-0/0/1',
                unit => 2004,
                tag => 2004,
                bandwidth => 50,
                mtu => 9000
            },
            {
                interface => 'ge-0/0/2',
                unit => 2004,
                tag => 2004,
                bandwidth => 0,
                mtu => 8080
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

warn "XML: " . $conf . "\n";
ok($conf eq $exp_xml, "Got expected xml");
