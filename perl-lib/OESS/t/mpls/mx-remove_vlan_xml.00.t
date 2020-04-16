#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;
use Test::More tests => 1;

use XML::LibXML;

use OESS::MPLS::Device::Juniper::MX;


# Purpose:
#
# Validate correct generation of L2VPN remove template.

my $exp_xml = "<configuration>
  <groups>
    <name>OESS</name>
    <interfaces>
      <interface>
        <name>ge-0/0/1</name>
        <unit operation='delete'>
          <name>2004</name>
        </unit>
      </interface>
      <interface>
        <name>ge-0/0/2</name>
        <unit operation='delete'>
          <name>2004</name>
        </unit>
      </interface>
    </interfaces>
    <class-of-service>
      <interfaces>
        <interface>
          <name>ge-0/0/2</name>
          <unit operation=\'delete\'>
            <name>2004</name>
          </unit>
        </interface>
      </interfaces>
    </class-of-service>
    <protocols>
      <mpls>
        <label-switched-path operation='delete'>
          <name>OESS-L2VPLS--LSP-3012--</name>
        </label-switched-path>
        <path operation='delete'>
          <name>OESS-L2VPLS--PATH-3012--</name>
        </path>
      </mpls>
    </protocols>
    <policy-options>
      <policy-statement>
        <name>L2VPLS-LSP-Policy</name>
        <term operation='delete'>
          <name>OESS-L2VPLS--3012--</name>
        </term>
      </policy-statement>
      <community operation='delete'>
        <name>OESS-L2VPLS-3012-Community</name>
      </community>
    </policy-options>
    <routing-instances>
      <instance operation='delete'>
        <name>OESS-L2VPLS-3012</name>
      </instance>
    </routing-instances>
  </groups>
</configuration>";

my $device = OESS::MPLS::Device::Juniper::MX->new(
    config => '/etc/oess/database.xml',
    loopback_addr => '127.0.0.1',
    mgmt_addr => '127.0.0.1',
    name => 'vmx-r0.testlab.grnoc.iu.edu',
    node_id => 1
);
$device->{jnx} = { conn_obj => 1 }; # Fake being connected. :)

my $conf = $device->remove_vlan_xml({
    circuit_name => 'circuit',
    interfaces => [
        {
            interface => 'ge-0/0/1',
            unit => 2004,
            tag => 2004
        },
        {
            interface => 'ge-0/0/2',
            unit => 2004,
            tag => 2004,
            bandwidth => 50
        }
    ],
    paths => [],
    circuit_id => 3012,
    site_id => 1,
    ckt_type => 'L2VPLS'
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
