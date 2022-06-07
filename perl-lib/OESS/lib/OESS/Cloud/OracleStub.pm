package OESS::Cloud::OracleStub;

use strict;
use warnings;

use Data::Dumper;
use JSON::XS;
use Log::Log4perl;


=head1 OESS::Cloud::OracleStub

    use OESS::Cloud::OracleStub

=cut


=head2 new

    my $oracle = new OESS::Cloud::OracleStub();

=cut
sub new {
    my $class = shift;
    my $args  = {
        config          => "/etc/oess/database.xml",
        config_obj      => undef,
        logger          => Log::Log4perl->get_logger("OESS.Cloud.OracleStub"),
        interconnect_id => undef,
        @_
    };
    my $self = bless $args, $class;

    die "Argument 'interconnect_id' was not passed to Oracle" if !defined $self->{interconnect_id};

    if (!defined $self->{config_obj}) {
        $self->{config_obj} = new OESS::Config(config_filename => $self->{config});
    }
    $self->{compartment_id} = $self->{config_obj}->oracle()->{$self->{interconnect_id}}->{compartment_id};

    return $self;
}

=head2 get_virtual_circuit

=cut
sub get_virtual_circuit {
    my $self = shift;
    my $id = shift;

    my $result;
    if ($id eq "UniqueVirtualCircuitId123") {
        $result = {
            "id" =>  "UniqueVirtualCircuitId123",
            "displayName" => "ProviderTestVirtualCircuit",
            "providerName" => "AlexanderGrahamBell",
            "providerServiceName" => "Layer2 Service",
            "providerServiceId" => "ocid1.providerservice.oc1.eu-frankfurt-1.abcd",
            "serviceType" => "LAYER2",
            "bgpManagement" => "CUSTOMER_MANAGED",
            "bandwidthShapeName" => "5Gbps",
            "oracleBgpAsn" => "561",
            "customerBgpAsn" => "1234",
            "crossConnectMappings" => [{
                "crossConnectOrCrossConnectGroupId" => "CrossConnect1",
                "vlan" => 1234,
                "oracleBgpPeeringIp" => "10.0.0.19/31",
                "customerBgpPeeringIp" => "10.0.0.18/31",
            },
            {
                "crossConnectOrCrossConnectGroupId" => "CrossConnect11",
                "vlan" => 1234,
                "customerBgpPeeringIp" => "10.0.0.20/31",
                "oracleBgpPeeringIp" => "10.0.0.21/31",
                "customerBgpPeeringIpv6" => "fd99:8e08:a70d:c444::2/127",
                "oracleBgpPeeringIpv6" => "fd99:8e08:a70d:c444::3/127",
            }],
            "lifecycleState" => "PENDING_PROVIDER",
            "providerState" => "INACTIVE",
            "bgpSessionState" => "DOWN",
            "region" => "IAD"
        };
    }

    if ($id eq "UniqueVirtualCircuitId456") {
        $result = {
            "id" =>  "UniqueVirtualCircuitId456",
            "displayName" => "ProviderTestVirtualCircuit",
            "providerName" => "AlexanderGrahamBell",
            "providerServiceName" => "Layer2 Service",
            "providerServiceId" => "ocid1.providerservice.oc1.eu-frankfurt-1.abcd",
            "serviceType" => "LAYER3",
            "bgpManagement" => "PROVIDER_MANAGED",
            "bandwidthShapeName" => "5Gbps",
            "oracleBgpAsn" => "561",
            "customerBgpAsn" => "1234",
            "crossConnectMappings" => [{
                "crossConnectOrCrossConnectGroupId" => "CrossConnect2",
                "vlan" => 1234,
                "oracleBgpPeeringIp" => "10.0.0.19/31",
                "customerBgpPeeringIp" => "10.0.0.18/31",
            }],
            "lifecycleState" => "PENDING_PROVIDER",
            "providerState" => "INACTIVE",
            "bgpSessionState" => "DOWN",
            "region" => "IAD",
            "type" => "PRIVATE"
        };
    }

    if ($id eq "UniqueVirtualCircuitId789") {
        $result = {
            "id" =>  "UniqueVirtualCircuitId789",
            "displayName" => "ProviderTestVirtualCircuit",
            "providerName" => "AlexanderGrahamBell",
            "providerServiceName" => "Layer2 Service",
            "providerServiceId" => "ocid1.providerservice.oc1.eu-frankfurt-1.abcd",
            "serviceType" => "LAYER3",
            "bgpManagement" => "ORACLE_MANAGED",
            "bandwidthShapeName" => "5Gbps",
            "oracleBgpAsn" => "561",
            "customerBgpAsn" => "1234",
            "crossConnectMappings" => [{
                "crossConnectOrCrossConnectGroupId" => "CrossConnect3",
                "vlan" => 1234,
                "oracleBgpPeeringIp" => "10.0.0.19/31",
                "customerBgpPeeringIp" => "10.0.0.18/31",
            }],
            "lifecycleState" => "PENDING_PROVIDER",
            "providerState" => "INACTIVE",
            "bgpSessionState" => "DOWN",
            "region" => "IAD",
            "type" => "PUBLIC"
        };
    }

    return ($result, undef);
}

=head2 get_virtual_circuits

    my ($virtual_circuits, $err) = $oracle->get_virtual_circuits();
    die $err if defined $err;

=cut
sub get_virtual_circuits {
    my $self = shift;

    my $results = [
        {
            "id" =>  "UniqueVirtualCircuitId123",
            "displayName" => "ProviderTestVirtualCircuit",
            "providerName" => "AlexanderGrahamBell",
            "providerServiceName" => "Layer2 Service",
            "providerServiceId" => "ocid1.providerservice.oc1.eu-frankfurt-1.abcd",
            "serviceType" => "LAYER2",
            "bgpManagement" => "CUSTOMER_MANAGED",
            "bandwidthShapeName" => "5Gbps",
            "oracleBgpAsn" => "561",
            "customerBgpAsn" => "1234",
            "crossConnectMappings" => [{
                "crossConnectOrCrossConnectGroupId" => "CrossConnect1",
                "vlan" => 1234,
                "customerBgpPeeringIp" => "10.0.0.18/31",
                "oracleBgpPeeringIp" => "10.0.0.19/31",
            },
            {
                "crossConnectOrCrossConnectGroupId" => "CrossConnect11",
                "vlan" => 1234,
                "customerBgpPeeringIp" => "10.0.0.20/31",
                "oracleBgpPeeringIp" => "10.0.0.21/31",
                "customerBgpPeeringIpv6" => "fd99:8e08:a70d:c444::2/127",
                "oracleBgpPeeringIpv6" => "fd99:8e08:a70d:c444::3/127",
            }],
            "lifecycleState" => "PENDING_PROVIDER",
            "providerState" => "INACTIVE",
            "bgpSessionState" => "DOWN",
            "region" => "IAD"
        },
        {
            "id" =>  "UniqueVirtualCircuitId456",
            "displayName" => "ProviderTestVirtualCircuit",
            "providerName" => "AlexanderGrahamBell",
            "providerServiceName" => "Layer2 Service",
            "providerServiceId" => "ocid1.providerservice.oc1.eu-frankfurt-1.abcd",
            "serviceType" => "LAYER3",
            "bgpManagement" => "PROVIDER_MANAGED",
            "bandwidthShapeName" => "5Gbps",
            "oracleBgpAsn" => "561",
            "customerBgpAsn" => "1234",
            "crossConnectMappings" => [{
                "crossConnectOrCrossConnectGroupId" => "CrossConnect2",
                "vlan" => 1234,
                "oracleBgpPeeringIp" => "10.0.0.19/31",
                "customerBgpPeeringIp" => "10.0.0.18/31",
            }],
            "lifecycleState" => "PENDING_PROVIDER",
            "providerState" => "INACTIVE",
            "bgpSessionState" => "DOWN",
            "region" => "IAD",
            "type" => "PRIVATE"
        },
        {
            "id" =>  "UniqueVirtualCircuitId789",
            "displayName" => "ProviderTestVirtualCircuit",
            "providerName" => "AlexanderGrahamBell",
            "providerServiceName" => "Layer2 Service",
            "providerServiceId" => "ocid1.providerservice.oc1.eu-frankfurt-1.abcd",
            "serviceType" => "LAYER3",
            "bgpManagement" => "ORACLE_MANAGED",
            "bandwidthShapeName" => "5Gbps",
            "oracleBgpAsn" => "561",
            "customerBgpAsn" => "1234",
            "crossConnectMappings" => [{
                "crossConnectOrCrossConnectGroupId" => "CrossConnect3",
                "vlan" => 1234,
                "oracleBgpPeeringIp" => "10.0.0.19/31",
                "customerBgpPeeringIp" => "10.0.0.18/31",
            }],
            "lifecycleState" => "PENDING_PROVIDER",
            "providerState" => "INACTIVE",
            "bgpSessionState" => "DOWN",
            "region" => "IAD",
            "type" => "PUBLIC"
        }
    ];
    return ($results, undef);
}

=head2 get_virtual_circuit_bandwidth_shapes

=cut
sub get_virtual_circuit_bandwidth_shapes {
    my $self = shift;
    my $provider_service_id = shift;

    return (
        [
            {
                'name' => '10 Gbps',
                'bandwidthInMbps' => 10000
            },
            {
                'name' => '2 Gbps',
                'bandwidthInMbps' => 2000
            },
            {
                'name' => '5 Gbps',
                'bandwidthInMbps' => 5000
            },
            {
                'name' => '1 Gbps',
                'bandwidthInMbps' => 1000
            },
            {
                'name' => '100 Gbps',
                'bandwidthInMbps' => 100000
            }
        ],
        undef
    );
}

=head2 get_fast_connect_provider_services

=cut
sub get_fast_connect_provider_services {
    my $self = shift;

    return (
        [
            {
                'requiredTotalCrossConnects' => 1,
                'description' => 'https://example.edu/',
                'privatePeeringBgpManagement' => 'PROVIDER_MANAGED',
                'providerName' => 'Example',
                'supportedVirtualCircuitTypes' => [
                    'PRIVATE',
                    'PUBLIC'
                ],
                'publicPeeringBgpManagement' => 'ORACLE_MANAGED',
                'bandwithShapeManagement' => 'CUSTOMER_MANAGED',
                'providerServiceKeyManagement' => 'PROVIDER_MANAGED',
                'customerAsnManagement' => 'PROVIDER_MANAGED',
                'type' => 'LAYER3',
                'id' => 'ocid1.providerservice.oc1.iad.0000',
                'providerServiceName' => 'Example L3'
            }
        ],
        undef
    );
}

=head2 update_virtual_circuit

=cut
sub update_virtual_circuit {
    my $self = shift;
    my $args = {
        virtual_circuit_id     => undef,
        bandwidth              => 1000,
        bfd                    => 0,
        mtu                    => 1500,
        oess_asn               => undef,
        name                   => '',    # providerServiceKeyName or alternatively referenceComment
        type                   => 'l2',
        cross_connect_mappings => [],
        @_
    };

    return (
        {
            "id" =>  "UniqueVirtualCircuitId123",
            "displayName" => "ProviderTestVirtualCircuit",
            "providerName" => "AlexanderGrahamBell",
            "providerServiceName" => "Layer2 Service",
            "providerServiceId" => "ocid1.providerservice.oc1.eu-frankfurt-1.abcd",
            "serviceType" => "LAYER2",
            "bgpManagement" => "CUSTOMER_MANAGED",
            "bandwidthShapeName" => "5Gbps",
            "oracleBgpAsn" => "561",
            "customerBgpAsn" => "1234",
            "crossConnectMappings" => [{
                "oracleBgpPeeringIp" => "10.0.0.19/31",
                "customerBgpPeeringIp" => "10.0.0.18/31",
            }],
            "lifecycleState" => "PENDING_PROVIDER",
            "providerState" => "INACTIVE",
            "bgpSessionState" => "DOWN",
            "region" => "IAD"
        },
        undef
    );
}

=head2 delete_virtual_circuit

=cut
sub delete_virtual_circuit {
    my $self = shift;
    my $id = shift;

    my $result;
    if ($id eq "UniqueVirtualCircuitId123") {
        $result = {
            "id" =>  "UniqueVirtualCircuitId123",
            "displayName" => "ProviderTestVirtualCircuit",
            "providerName" => "AlexanderGrahamBell",
            "providerServiceName" => "Layer2 Service",
            "providerServiceId" => "ocid1.providerservice.oc1.eu-frankfurt-1.abcd",
            "serviceType" => "LAYER2",
            "bgpManagement" => "CUSTOMER_MANAGED",
            "bandwidthShapeName" => "5Gbps",
            "oracleBgpAsn" => "561",
            "customerBgpAsn" => "1234",
            "crossConnectMappings" => [{
                "crossConnectOrCrossConnectGroupId" => "CrossConnect1",
                "vlan" => 1234,
                "oracleBgpPeeringIp" => "10.0.0.19/31",
                "customerBgpPeeringIp" => "10.0.0.18/31",
            },
            {
                "crossConnectOrCrossConnectGroupId" => "CrossConnect11",
                "vlan" => 1234,
                "customerBgpPeeringIp" => "10.0.0.20/31",
                "oracleBgpPeeringIp" => "10.0.0.21/31",
                "customerBgpPeeringIpv6" => "fd99:8e08:a70d:c444::2/127",
                "oracleBgpPeeringIpv6" => "fd99:8e08:a70d:c444::3/127",
            }],
            "lifecycleState" => "TERMINATING",
            "providerState" => "ACTIVE",
            "bgpSessionState" => "UP",
            "region" => "IAD"
        };
    }

    if ($id eq "UniqueVirtualCircuitId456") {
        $result = {
            "id" =>  "UniqueVirtualCircuitId456",
            "displayName" => "ProviderTestVirtualCircuit",
            "providerName" => "AlexanderGrahamBell",
            "providerServiceName" => "Layer2 Service",
            "providerServiceId" => "ocid1.providerservice.oc1.eu-frankfurt-1.abcd",
            "serviceType" => "LAYER3",
            "bgpManagement" => "PROVIDER_MANAGED",
            "bandwidthShapeName" => "5Gbps",
            "oracleBgpAsn" => "561",
            "customerBgpAsn" => "1234",
            "crossConnectMappings" => [{
                "crossConnectOrCrossConnectGroupId" => "CrossConnect2",
                "vlan" => 1234,
                "oracleBgpPeeringIp" => "10.0.0.19/31",
                "customerBgpPeeringIp" => "10.0.0.18/31",
            }],
            "lifecycleState" => "TERMINATING",
            "providerState" => "ACTIVE",
            "bgpSessionState" => "UP",
            "region" => "IAD",
            "type" => "PRIVATE"
        };
    }

    if ($id eq "UniqueVirtualCircuitId789") {
        $result = {
            "id" =>  "UniqueVirtualCircuitId789",
            "displayName" => "ProviderTestVirtualCircuit",
            "providerName" => "AlexanderGrahamBell",
            "providerServiceName" => "Layer2 Service",
            "providerServiceId" => "ocid1.providerservice.oc1.eu-frankfurt-1.abcd",
            "serviceType" => "LAYER3",
            "bgpManagement" => "ORACLE_MANAGED",
            "bandwidthShapeName" => "5Gbps",
            "oracleBgpAsn" => "561",
            "customerBgpAsn" => "1234",
            "crossConnectMappings" => [{
                "crossConnectOrCrossConnectGroupId" => "CrossConnect3",
                "vlan" => 1234,
                "oracleBgpPeeringIp" => "10.0.0.19/31",
                "customerBgpPeeringIp" => "10.0.0.18/31",
            }],
            "lifecycleState" => "TERMINATING",
            "providerState" => "ACTIVE",
            "bgpSessionState" => "UP",
            "region" => "IAD",
            "type" => "PUBLIC"
        };
    }

    return ($result, undef);
}

return 1;
