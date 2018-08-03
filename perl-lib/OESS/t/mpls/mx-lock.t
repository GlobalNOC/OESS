use strict;
use warnings;

use Data::Dumper;

use OESS::Mock;
use OESS::MPLS::Device::Juniper::MX;
use XML::LibXML;

use Test::More tests => 4;


my $device = OESS::MPLS::Device::Juniper::MX->new(
    config        => '/etc/oess/database.xml',
    loopback_addr => '127.0.0.1',
    mgmt_addr     => '127.0.0.1',
    name          => 'vmx-r0.testlab.grnoc.iu.edu',
    node_id       => 1
);

my $mock = OESS::Mock->new;
$device->{jnx} = $mock;

# Mock subroutines required for add_vlan but not under test.
$mock->new_sub(
    name => 'connected',
    result => 1
);

$mock->new_sub(
    name   => 'open_configuration',
    result => 1
);


$mock->new_sub(
    name   => 'get_dom',
    result => XML::LibXML->load_xml(string => '<?xml version="1.0"?>
<rpc-reply xmlns="urn:ietf:params:xml:ns:netconf:base:1.0" xmlns:junos="http://xml.juniper.net/junos/15.1F6/junos" message-id="6">
<ok/>
</rpc-reply>')
);

my $ok = $device->lock();
ok($ok == 1, "lock succeeded when ok message received.");


$mock->new_sub(
    name   => 'get_dom',
    result => XML::LibXML->load_xml(string => '<?xml version="1.0"?>
<rpc-reply xmlns="urn:ietf:params:xml:ns:netconf:base:1.0" xmlns:junos="http://xml.juniper.net/junos/15.1F6/junos" message-id="8">
    <rpc-error>
        <error-severity>warning</error-severity>
        <error-message>uncommitted changes will be discarded on exit</error-message>
    </rpc-error>
</rpc-reply>')
);

$ok = $device->lock();
ok($ok == 1, "lock reported success when warning message received.");


$mock->new_sub(
    name   => 'get_dom',
    result => XML::LibXML->load_xml(string => '<?xml version="1.0"?>
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

$ok = $device->lock();
ok($ok == 0, "lock failed when error message received.");


my $err = $mock->sub_called(
    name  => 'open_configuration',
    count => 3
);

ok(!defined $err, "open_configuration called 3 times.");
warn "$err" if defined $err;
