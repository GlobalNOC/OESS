#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;


use GRNOC::Log;
use Test::More tests => 5;
my $logger = GRNOC::Log->new( level => 'DEBUG');

use OESS::Database;
use OESS::Mock;
use OESS::MPLS::Device::Juniper::MX;


# MX overrides unit_name_available to return 1.
{
    package MX;

    use base 'OESS::MPLS::Device::Juniper::MX';

    sub unit_name_available {
        my $self = shift;
        return 1;
    }
}

# DOM object provides a toString method returning XML that might be
# returned from a network device. Used as a result to get_dom.
{
    package DOM;

    sub new {
        my $class = shift;
        my $self  = {
            xml => shift
        };

        return bless $self, $class;
    }

    sub toString {
        my $self = shift;
        return $self->{xml};
    }
}

my $device = MX->new(
    config => '/etc/oess/database.xml',
    loopback_addr => '127.0.0.1',
    mgmt_addr => '127.0.0.1',
    name => 'vmx-r0.testlab.grnoc.iu.edu',
    node_id => 1
);

my $mock = OESS::Mock->new;
$device->{jnx} = $mock;

# Mock subroutines required for add_vlan but not under test.
$mock->new_sub(
    name => 'connected',
    result => 1
);

$mock->new_sub(
    name   => 'edit_config',
    result => 1
);

$mock->new_sub(
    name    => 'open_configuration',
    result => 1
);

$mock->new_sub(
    name   => 'get_dom',
    result => DOM->new('<?xml version="1.0"?>
<rpc-reply xmlns="urn:ietf:params:xml:ns:netconf:base:1.0" xmlns:junos="http://xml.juniper.net/junos/15.1F6/junos" message-id="6">
<ok/>
</rpc-reply>')
);

my $ok = $device->add_vlan({
    name => 'circuit',
    endpoints => [
        {
            interface => 'ge-0/0/1',
            unit => 2004,
            tag => 2004
        },
        {
            interface => 'ge-0/0/2',
            unit => 2004,
            tag => 2004
        }
    ],
    paths => [],
    circuit_id => 3012,
    site_id => 1,
    ckt_type => 'L2VPLS'
});
ok($ok == 1, "add_vlan succeeded when ok message received.");


$mock->new_sub(
    name   => 'get_dom',
    result => DOM->new('<?xml version="1.0"?>
<rpc-reply xmlns="urn:ietf:params:xml:ns:netconf:base:1.0" xmlns:junos="http://xml.juniper.net/junos/15.1F6/junos" message-id="8">
    <rpc-error>
        <error-severity>warning</error-severity>
        <error-message>uncommitted changes will be discarded on exit</error-message>
    </rpc-error>
</rpc-reply>')
);

$ok = $device->add_vlan({
    name => 'circuit',
    endpoints => [
        {
            interface => 'ge-0/0/1',
            tag => 2004,
            unit => 2004
        },
        {
            interface => 'ge-0/0/2',
            tag => 2004,
            unit => 2004,
            bandwidth => 50
        }
    ],
    paths => [],
    circuit_id => 3012,
    site_id => 1,
    ckt_type => 'L2VPLS'
});
ok($ok == 1, "add_vlan reported success when warning message received.");


$mock->new_sub(
    name   => 'get_dom',
    result => DOM->new('<?xml version="1.0"?>
<rpc-reply xmlns="urn:ietf:params:xml:ns:netconf:base:1.0" xmlns:junos="http://xml.juniper.net/junos/15.1F6/junos" message-id="7">
    <commit-results>
        <load-success/>
        <rpc-error>
            <error-type>protocol</error-type>
            <error-tag>operation-failed</error-tag>
            <error-severity>error</error-severity>
            <source-daemon>dcd</source-daemon>
            <error-path>[edit interfaces ge-0/0/2]</error-path>
            <error-info>
            <bad-element>unit 2000</bad-element>
            </error-info>
            <error-message>logical unit is not allowed on aggregated links</error-message>
        </rpc-error>
        <rpc-error>
            <error-type>protocol</error-type>
            <error-tag>operation-failed</error-tag>
            <error-severity>error</error-severity>
            <error-message>configuration check-out failed</error-message>
        </rpc-error>
    </commit-results>
</rpc-reply>')
);

$ok = $device->add_vlan({
    name => 'circuit',
    endpoints => [
        {
            interface => 'ge-0/0/1',
            unit => 2004,
            tag => 2004
        },
        {
            interface => 'ge-0/0/2',
            unit => 2004,
            tag => 2004
        }
    ],
    paths => [],
    circuit_id => 3012,
    site_id => 1,
    ckt_type => 'L2VPLS'
});

ok($ok == 0, "add_vlan failed when error message received.");

my $expected_config = '<configuration><groups><name>OESS</name>
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
  <class-of-service>
    <interfaces>
      <interface>
        <name>ge-0/0/2</name>
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
</groups></configuration>
';

# Validates edit_config was called 3 times and that the last call was
# passed $expected_config.
my $err = $mock->sub_called(
    name  => 'edit_config',
    count => 2,
    args  => {
        target => 'candidate',
        config => $expected_config
    }
);

ok(!defined $err, "edit_config called 2 times with expected NetConf payload.");
warn "$err" if defined $err;

$err = $mock->sub_called(
    name  => 'get_dom',
    count => 1
);

ok(!defined $err, "get_dom called 1 times.");
warn "$err" if defined $err;
