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
    name   => 'get_mpls_lsp_information',
    result => 1
);

$mock->new_sub(
    name   => 'get_dom',
    result => XML::LibXML->load_xml(string => '<rpc-reply xmlns="urn:ietf:params:xml:ns:netconf:base:1.0" xmlns:junos="http://xml.juniper.net/junos/15.1F6/junos" message-id="7">
<mpls-lsp-information xmlns="http://xml.juniper.net/junos/15.1F6/junos-routing">
<rsvp-session-data>
<session-type>Ingress</session-type>
<count>1</count>
<rsvp-session style="detail">
<mpls-lsp>
<destination-address>172.16.0.6</destination-address>
<source-address>172.16.0.0</source-address>
<lsp-state>Up</lsp-state>
<route-count>0</route-count>
<name>I2-LAB0-MX960-1-LSP-6</name>
<lsp-description/>
<active-path>I2-LAB0-MX960-1-LSP-6-primary (primary)</active-path>
<lsp-type>Static Configured</lsp-type>
<egress-label-operation>Penultimate hop popping</egress-label-operation>
<load-balance>random</load-balance>
<mpls-lsp-attributes>
<encoding-type>Packet</encoding-type>
<switching-type>Packet</switching-type>
<gpid>IPv4</gpid>
<mpls-lsp-upstream-label>
</mpls-lsp-upstream-label>
</mpls-lsp-attributes>
<revert-timer>600</revert-timer>
<mpls-lsp-path>
<title>Primary</title>
<name>I2-LAB0-MX960-1-LSP-6-primary</name>
<path-active/>
<path-state>Up</path-state>
<setup-priority>0</setup-priority>
<hold-priority>0</hold-priority>
<optimize-timer>600</optimize-timer>
<srlg heading="SRLG:">
<srlg-name>SRLG-01</srlg-name>
<srlg-name>SRLG-02</srlg-name>
</srlg>
<cspf-status>Reoptimization in 191 second(s).</cspf-status>
<cspf-status>
Computed ERO (S [L] denotes strict [loose] hops): (CSPF metric: 40)
</cspf-status>
<explicit-route heading="          ">
<address>172.16.0.13</address>
<explicit-route-type>S</explicit-route-type>
<address>172.16.0.17</address>
<explicit-route-type>S</explicit-route-type>
<address>172.16.0.19</address>
<explicit-route-type>S</explicit-route-type>
<address>172.16.0.31</address>
<explicit-route-type>S</explicit-route-type>
</explicit-route>
<received-rro>
Received RRO (ProtectionFlag 1=Available 2=InUse 4=B/W 8=Node 10=SoftPreempt 20=Node-ID):
      172.16.0.13 172.16.0.17 172.16.0.19 172.16.0.31
</received-rro>
<path-history>
<sequence-number>2177</sequence-number>
<time>Jan 12 16:16:16.845</time>
<log>CSPF: computation result ignored, new path no benefit[105 times]</log>
<route/>
</path-history>
</mpls-lsp-path>
<lsp-creation-time>Tue Oct 24 15:19:48 2017
</lsp-creation-time>
</mpls-lsp>
</rsvp-session>
</rsvp-session-data>
</mpls-lsp-information>
</rpc-reply>')
);

my $table = 'bgp.l2vpn.0';
my $lsps = [{
    sessions => [
        {
            'destination-address' => '172.16.0.6',
            'name' => 'I2-LAB0-MX960-1-LSP-6',
            'lsp-type' => 'Static Configured',
            'lsp-state' => 'Up',
            'description' => '',
            'paths' => [
                {
                    'path-state' => 'Up',
                    'explicit-route' => {
                        'explicit-route-type' => '',
                        'addresses' => [
                            '172.16.0.13',
                            '172.16.0.17',
                            '172.16.0.19',
                            '172.16.0.31'
                        ]
                    },
                    'name' => 'I2-LAB0-MX960-1-LSP-6-primary',
                    'setup-priority' => '0',
                    'smart-optimize-timer' => '',
                    'path-active' => '',
                    'received-rro' => 'Received RRO (ProtectionFlag 1=Available 2=InUse 4=B/W 8=Node 10=SoftPreempt 20=Node-ID):
      172.16.0.13 172.16.0.17 172.16.0.19 172.16.0.31',
                    'title' => 'Primary',
                    'hold-priority' => '0'
                }
            ],
            'egress-label-operation' => 'Penultimate hop popping',
            'active-path' => 'I2-LAB0-MX960-1-LSP-6-primary (primary)',
            'route-count' => '0',
            'revert-timer' => '600',
            'source-address' => '172.16.0.0',
            'load-balance' => 'random',
            'attributes' => {
                'encoding-type' => 'Packet',
                'switching-type' => '',
                'gpid' => ''
            }
        }
    ],
    session_type => 'Ingress',
    count => '1'
}];

my $result = $device->get_LSPs();
my ($ok, $stack) = Test::Deep::cmp_details($result, $lsps);
ok($ok, "LSP paths discovered");

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

$result = $device->get_LSPs();
($ok, $stack) = Test::Deep::cmp_details($result, []);
ok($ok, "empty array returned when error message received.");


my $err = $mock->sub_called(
    name  => 'get_mpls_lsp_information',
    count => 2
);

ok(!defined $err, "get_mpls_lsp_information called 2 times.");
warn "$err" if defined $err;
