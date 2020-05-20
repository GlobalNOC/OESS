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
  <groups>
    <name>OESS</name>
    <interfaces>
      <interface>
        <name>e15/1</name>
        <unit operation="delete">
          <name>201</name>
        </unit>
      </interface>
      <interface>
        <name>e15/1</name>
        <unit operation="delete">
          <name>601</name>
        </unit>
      </interface>
    </interfaces>

    <class-of-service>
      <interfaces>
        <interface>
          <name>e15/1</name>
          <unit operation="delete">
            <name>201</name>
          </unit>
        </interface>
      </interfaces>
    </class-of-service>

    <routing-instances>
      <instance operation="delete">
        <name>OESS-L3VPN-3012</name>
      </instance>
    </routing-instances>
    <policy-options>
      <policy-statement operation="delete"><name>OESS-L3VPN-3012-IMPORT</name></policy-statement>
      <policy-statement operation="delete"><name>OESS-L3VPN-3012-EXPORT</name></policy-statement>
      <policy-statement operation="delete"><name>OESS-L3VPN-3012-IN</name></policy-statement>
      <policy-statement operation="delete"><name>OESS-L3VPN-3012-OUT</name></policy-statement>
      <community operation="delete"><name>OESS-L3VPN-3012</name></community>
      <community operation="delete"><name>OESS-L3VPN-3012-BGP</name></community>
    </policy-options>
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

my $conf = $device->remove_vrf_xml({
    local_asn => 555,
    endpoints => [
        {
            interface => 'e15/1',
            unit => 201,
            tag => 201,
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
            interface => 'e15/1',
            unit => 601,
            tag => 601,
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
