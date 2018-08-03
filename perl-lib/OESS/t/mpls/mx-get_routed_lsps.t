use strict;
use warnings;

use Data::Dumper;

use OESS::Mock;
use OESS::MPLS::Device::Juniper::MX;
use XML::LibXML;

use Test::More tests => 3;


my $device = OESS::MPLS::Device::Juniper::MX->new(
    config        => '/etc/oess/database.xml',
    loopback_addr => '127.0.0.1',
    mgmt_addr     => '127.0.0.1',
    name          => 'vmx-r0.testlab.grnoc.iu.edu',
    node_id       => 1
);
$device->{'root_namespace'} = 'http://xml.juniper.net/junos/15.1F6/';


my $mock = OESS::Mock->new;
$device->{jnx} = $mock;

# Mock subroutines required for add_vlan but not under test.
$mock->new_sub(
    name => 'connected',
    result => 1
);

$mock->new_sub(
    name => 'has_error',
    result => 0
);

$mock->new_sub(
    name   => 'get_route_information',
    result => 1
);

$mock->new_sub(
    name   => 'get_dom',
    result => XML::LibXML->load_xml(string => '<?xml version="1.0"?>
<rpc-reply xmlns="urn:ietf:params:xml:ns:netconf:base:1.0" xmlns:junos="http://xml.juniper.net/junos/15.1F6/junos" message-id="5">
<route-information xmlns="http://xml.juniper.net/junos/15.1F6/junos-routing">
<!-- keepalive -->
<route-table>
<table-name>bgp.l2vpn.0</table-name>
<destination-count>1</destination-count>
<total-route-count>1</total-route-count>
<active-route-count>1</active-route-count>
<holddown-route-count>0</holddown-route-count>
<hidden-route-count>0</hidden-route-count>
<rt style="brief">
<rt-destination>11537:3025:1:1</rt-destination>
<rt-prefix-length emit="emit">96</rt-prefix-length>
<rt-entry>
<active-tag>*</active-tag>
<current-active/>
<last-active/>
<protocol-name>BGP</protocol-name>
<preference>170</preference>
<age seconds="3955">01:05:55</age>
<local-preference>100</local-preference>
<learned-from>172.16.0.0</learned-from>
<as-path>I
</as-path>
<validation-state>unverified</validation-state>
<nh>
<selected-next-hop/>
<to>172.16.0.12</to>
<via>ae1.20</via>
<lsp-name>I2-LAB1-LAB0-LSP-0</lsp-name>
</nh>
</rt-entry>
</rt>
</route-table>
</route-information>
</rpc-reply>')
);

my $table = 'bgp.l2vpn.0';
my $circuits = {
    '3025' => {
        'circuit_id' => '3025',
        'interfaces' => [
            {
                'node' => 'vmx-r1.testlab.grnoc.iu.edu',
                'local' => '1',
                'mac_addrs' => [],
                'interface_description' => 'R1 -> R2',
                'port_no' => undef,
                'node_id' => '4',
                'urn' => undef,
                'interface' => 'ge-0/0/1',
                'tag' => '300',
                'role' => 'unknown'
            }
        ],
        'a_side' => '4',
        'circuit_name' => 'admin-5056cdda-f6df-11e7-94cd-fa163e341ea2',
        'site_id' => 2,
        'paths' => [
            {
                'dest' => '172.16.0.0',
                'name' => 'PRIMARY',
                'mpls_path_type' => 'loose',
                'dest_node' => '1'
            }
        ],
        'ckt_type' => 'L2VPN',
        'state' => 'active'
    }
};

my $circuit_to_lsp = $device->get_routed_lsps(table => $table, circuits => $circuits);
my ($ok, $stack) = Test::Deep::cmp_details(
    $circuit_to_lsp,
    {
        3025 => [
            'I2-LAB1-LAB0-LSP-0'
        ]
    }
);
ok($ok, "LSP discovered");

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

$circuit_to_lsp = $device->get_routed_lsps(table => $table, circuits => $circuits);
($ok, $stack) = Test::Deep::cmp_details($circuit_to_lsp, {});
ok($ok, "empty hash returned when error message received.");


my $err = $mock->sub_called(
    name  => 'get_route_information',
    count => 2
);

ok(!defined $err, "close_configuration called 3 times.");
warn "$err" if defined $err;
