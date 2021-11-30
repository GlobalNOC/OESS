package OESS::Cloud::AzureStub;

use strict;
use warnings;

use Data::Dumper;
use JSON::XS;
use Log::Log4perl;

=head1 OESS::Cloud::AzureStub

=cut


=head2 new

    my $azure = new OESS::Cloud::AzureStub();

=cut
sub new {
    my $class = shift;
    my $args  = {
        config => "/etc/oess/database.xml",
        logger => Log::Log4perl->get_logger("OESS.Cloud.AzureStub"),
        @_
    };
    my $self = bless $args, $class;

    return $self;
}

=head2 expressRouteCrossConnections

=cut
sub expressRouteCrossConnections {
    my $self = shift;
    my $interconnect_id = shift;

    return [
        {
            'etag'     => 'W/"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"', # A unique read-only string that changes whenever the resource is updated.
            'location' => 'westus',
            'name'     => '11111111-1111-1111-1111-111111111111',
            'type'     => 'Microsoft.Network/expressRouteCrossConnections',
            'id'       => '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/CrossConnection-SiliconValleyTest/providers/Microsoft.Network/expressRouteCrossConnections/11111111-1111-1111-1111-111111111111',
            'properties' => {
                'peerings' => [],
                'peeringLocation' => 'Silicon Valley Test',
                'expressRouteCircuit' => {
                    'id' => '/subscriptions/00000000-0000-0000-0000-111111111111/resourceGroups/oess-test-api/providers/Microsoft.Network/expressRouteCircuits/oess-test-circuit'
                },
                'bandwidthInMbps' => 50,
                'serviceProviderProvisioningState' => 'Provisioned',
                'provisioningState' => 'Succeeded'
            }
        }
    ];
}

=head2 expressRouteCrossConnection

=cut
sub expressRouteCrossConnection {
    my $self = shift;
    my $interconnect_id = shift;
    my $service_key     = shift;

    return {
        'etag' => 'W/"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"', # A unique read-only string that changes whenever the resource is updated.
        'location' => 'westus',
        'name' => '11111111-1111-1111-1111-111111111111',
        'type' => 'Microsoft.Network/expressRouteCrossConnections',
        'id' => '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/CrossConnection-SiliconValleyTest/providers/Microsoft.Network/expressRouteCrossConnections/11111111-1111-1111-1111-111111111111',
        'properties' => {
            'bandwidthInMbps' => 50,
            'serviceProviderProvisioningState' => 'Provisioned',
            'provisioningState' => 'Succeeded',
            'sTag' => 2,
            'peerings' => [
                {
                    'name' => 'AzurePrivatePeering',
                    'type' => 'Microsoft.Network/expressRouteCrossConnections/peerings',
                    'id' => '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/CrossConnection-SiliconValleyTest/providers/Microsoft.Network/expressRouteCrossConnections/11111111-1111-1111-1111-111111111111/peerings/AzurePrivatePeering',
                    'properties' => {
                        'primaryPeerAddressPrefix' => '192.168.100.248/30',
                        'peerASN' => 64512, # 2-byte private asn
                        'azureASN' => 12076,
                        'provisioningState' => 'Succeeded',
                        'gatewayManagerEtag' => '',
                        'vlanId' => 100,
                        'state' => 'Enabled',
                        'secondaryPeerAddressPrefix' => '192.168.100.252/30',
                        'secondaryAzurePort' => '',
                        'lastModifiedBy' => 'Customer',
                        'peeringType' => 'AzurePrivatePeering',
                        'primaryAzurePort' => ''
                    }
                }
            ],
            'peeringLocation' => 'Silicon Valley Test',
            'expressRouteCircuit' => {
                'id' => '/subscriptions/00000000-0000-0000-0000-111111111111/resourceGroups/oess-test-api/providers/Microsoft.Network/expressRouteCircuits/oess-test-circuit'
            },
            'secondaryAzurePort' => 'OessTest-SJC-TEST-00GMR-CIS-2-SEC-A',
            'primaryAzurePort' => 'OessTest-SJC-TEST-00GMR-CIS-1-PRI-A'
        }
    };
}

return 1;
