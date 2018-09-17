use strict;
use warnings;

use Data::Dumper;

use OESS::Mock;
use OESS::MPLS::Device::Juniper::MX;

use Test::More tests => 1;


my $device = OESS::MPLS::Device::Juniper::MX->new(
    config => '/etc/oess/database.xml',
    loopback_addr => '127.0.0.1',
    mgmt_addr => '127.0.0.1',
    name => 'vmx-r0.testlab.grnoc.iu.edu',
    node_id => 1
);

my $mock = OESS::Mock->new;
$device->{jnx} = $mock;

my $exp_xml = '<configuration>
  <interfaces>
    
    <interface>
      <name>ge-0/0/1</name>
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

</configuration>';

my $conf = $device->xml_configuration(
    [{
        circuit_name => 'circuit',
        interfaces => [
            {
                interface => 'ge-0/0/1',
                tag => 2004
            },
            {
                interface => 'ge-0/0/2',
                tag => 2004
            }
        ],
        paths => [],
        circuit_id => 3012,
        site_id => 1,
        state => 'active',
        ckt_type => 'L2VPLS'
    }],
    [],
    ''
);

warn "XML: " . $conf . "\n";
ok($conf eq $exp_xml, "Got expected xml");
