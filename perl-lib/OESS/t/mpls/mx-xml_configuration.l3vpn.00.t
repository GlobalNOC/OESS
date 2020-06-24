#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;
use Test::More tests => 1;

use XML::LibXML;

use OESS::MPLS::Device::Juniper::MX;


# Purpose:
#
# Validate correct generation of L3VPN L3Connection template.


my $exp_xml = '<configuration>
  <groups operation="delete">
    <name>OESS</name>
  </groups>
  <groups>
    <name>OESS</name>
    <interfaces>
      <interface>
        <name>ge-0/0/1</name>
        <unit>
          <name>2004</name>
          <description>OESS-L3VPN-3012</description>
          <vlan-tags>
            <outer>2004</outer>
            <inner>30</inner>
          </vlan-tags>
          <family>
            <inet>
              <mtu>9000</mtu>
              <address>
                <name>192.168.2.2/31</name>
              </address>
            </inet>
          </family>
        </unit>
      </interface>
      <interface>
        <name>ge-0/0/2</name>
        <unit>
          <name>2004</name>
          <description>OESS-L3VPN-3012</description>
          <vlan-id>2004</vlan-id>
          <family>
            <inet6>
              <address>
                <name>fd97:ab53:51b7:017b::4/127</name>
              </address>
            </inet6>
          </family>
        </unit>
      </interface>
    </interfaces>
    <class-of-service>
      <interfaces>
        <interface>
          <name>ge-0/0/1</name>
          <unit>
            <name>2004</name>
            <shaping-rate>
              <rate>50m</rate>
            </shaping-rate>
          </unit>
        </interface>
      </interfaces>
    </class-of-service>
    <routing-instances>
      <instance>
        <name>OESS-L3VPN-3012</name>
        <instance-type>vrf</instance-type>
        <interface>
          <name>ge-0/0/1.2004</name>
        </interface>
        <interface>
          <name>ge-0/0/2.2004</name>
        </interface>
        <route-distinguisher>
          <rd-type>127.0.0.1:3012</rd-type>
        </route-distinguisher>
        <vrf-import>OESS-L3VPN-3012-IMPORT</vrf-import>
        <vrf-export>OESS-L3VPN-3012-EXPORT</vrf-export>
        <vrf-table-label/>
        <routing-options>
          <router-id>127.0.0.1</router-id>
          <autonomous-system>
            <as-number>555</as-number>
            <independent-domain/>
          </autonomous-system>
        </routing-options>
        <protocols>
          <bgp>
            <log-updown/>
            <group>
              <name>OESS-L3VPN-3012-BGP</name>
              <family>
                <inet>
                  <unicast>
                    <prefix-limit>
                      <maximum/>
                      <teardown>
                        <limit-threshold>90</limit-threshold>
                        <idle-timeout>
                          <timeout>30</timeout>
                        </idle-timeout>
                      </teardown>
                    </prefix-limit>
                  </unicast>
                </inet>
              </family>
              <local-as>
                <as-number>555</as-number>
              </local-as>
              <neighbor>
                <name>192.168.2.3</name>
                <description>OESS-L3VPN-3012</description>
                <import>OESS-L3VPN-3012-IN</import>
                <authentication-key>md5key</authentication-key>
                <export>OESS-L3VPN-3012-OUT</export>
                <peer-as>666</peer-as>
              </neighbor>
            </group>
            <group>
              <name>OESS-L3VPN-3012-BGP-V6</name>
              <family>
                <inet6>
                  <unicast>
                    <prefix-limit>
                      <maximum/>
                      <teardown>
                        <limit-threshold>90</limit-threshold>
                        <idle-timeout>
                          <timeout>30</timeout>
                        </idle-timeout>
                      </teardown>
                    </prefix-limit>
                  </unicast>
                </inet6>
              </family>
              <local-as>
                <as-number>555</as-number>
              </local-as>
              <neighbor>
                <name>fd97:ab53:51b7:017b::5</name>
                <description>OESS-L3VPN-3012</description>
                <import>OESS-L3VPN-3012-IN</import>
                <export>OESS-L3VPN-3012-OUT</export>
                <peer-as>777</peer-as>
              </neighbor>
            </group>
          </bgp>
        </protocols>
      </instance>
    </routing-instances>
    <policy-options>
      <policy-statement>
        <name>OESS-L3VPN-3012-EXPORT</name>
        <term>
          <name>direct</name>
          <from>
            <protocol>direct</protocol>
          </from>
          <then>
            <community>
              <add/>
              <community-name>OESS-L3VPN-3012</community-name>
            </community>
            <accept/>
          </then>
        </term>
        <term>
          <name>bgp</name>
          <from>
            <protocol>bgp</protocol>
          </from>
          <then>
            <community>
              <add/>
              <community-name>OESS-L3VPN-3012</community-name>
            </community>
            <accept/>
          </then>
        </term>
        <term>
          <name>reject</name>
          <then>
            <reject/>
          </then>
        </term>
      </policy-statement>
      <policy-statement>
        <name>OESS-L3VPN-3012-IMPORT</name>
        <term>
          <name>import</name>
          <from>
            <community>OESS-L3VPN-3012</community>
          </from>
          <then>
            <accept/>
          </then>
        </term>
        <term>
          <name>reject</name>
          <then>
            <reject/>
          </then>
        </term>
      </policy-statement>
      <policy-statement>
        <name>OESS-L3VPN-3012-IN</name>
        <term>
          <name>remove-comms-rt</name>
          <then>
            <community>
              <delete/>
              <community-name>I2CLOUD-EXTENDED-TARGET</community-name>
            </community>
            <next>term</next>
          </then>
        </term>
        <term>
          <name>import-bgp</name>
          <from>
            <protocol>bgp</protocol>
          </from>
          <then>
            <community>
              <add/>
              <community-name>OESS-L3VPN-3012-BGP</community-name>
            </community>
            <accept/>
          </then>
        </term>
      </policy-statement>
      <policy-statement>
        <name>OESS-L3VPN-3012-OUT</name>
        <term>
          <name>remove-comms-rt</name>
          <then>
            <community>
              <delete/>
              <community-name>I2CLOUD-EXTENDED-TARGET</community-name>
            </community>
            <next>term</next>
          </then>
        </term>
        <term>
          <name>export-bgp</name>
          <from>
            <protocol>bgp</protocol>
          </from>
          <then>
            <accept/>
          </then>
        </term>
        <term>
          <name>export-direct</name>
          <from>
            <protocol>direct</protocol>
          </from>
          <then>
            <community>
              <add/>
              <community-name>OESS-L3VPN-3012-BGP</community-name>
            </community>
            <accept/>
          </then>
        </term>
      </policy-statement>
      <community>
        <name>OESS-L3VPN-3012</name>
        <members>target:555:3012</members>
      </community>
      <community>
        <name>OESS-L3VPN-3012-BGP</name>
        <members>555:3012</members>
      </community>
    </policy-options>
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
    [],
    [{
        local_asn => 555,
        endpoints => [
            {
                interface => 'ge-0/0/1',
                unit => 2004,
                tag => 2004,
                inner_tag => 30, # CHECK: QinQ
                bandwidth => 50, # CHECK: class-of-service added
                mtu => 9000,     # CHECK: family > ccc > mtu added
                peers => [
                    {
                        local_ip  => '192.168.2.2/31',
                        peer_ip => '192.168.2.3/31',
                        md5_key => 'md5key',
                        bfd => 0,
                        peer_asn => 666,
                        ip_version => 'ipv4'
                    }
                ]
            },
            {
                interface => 'ge-0/0/2',
                unit => 2004,
                tag => 2004,
                bandwidth => 0,  # CHECK: class-of-service omitted
                mtu => 0,        # CHECK: family > ccc > mtu omitted
                peers => [
                    {
                        local_ip  => 'fd97:ab53:51b7:017b::4/127',
                        peer_ip => 'fd97:ab53:51b7:017b::5/127',
                        md5_key => undef,
                        bfd => 1,
                        peer_asn => 777,
                        ip_version => 'ipv6'
                    }
                ]
            }
        ],
        switch => { loopback => '127.0.0.1' },
        vrf_id => 3012,
        state => 'active'
    }],
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
