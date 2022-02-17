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
        config => "/etc/oess/database.xml",
        logger => Log::Log4perl->get_logger("OESS.Cloud.OracleStub"),
        @_
    };
    my $self = bless $args, $class;

    return $self;
}

=head2 get_virtual_circuit

=cut
sub get_virtual_circuit {
    my $self = shift;
    my $id = shift;

    if ($id eq "UniqueVirtualCircuitId123") {
        return {
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
            }],
            "lifecycleState" => "PENDING_PROVIDER",
            "providerState" => "INACTIVE",
            "bgpSessionState" => "DOWN",
            "region" => "IAD"
        };
    }

    if ($id eq "UniqueVirtualCircuitId456") {
        return {
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
        return {
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

    return;
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

=head2 update_virtual_circuit

=cut
sub update_virtual_circuit {
    my $self = shift;
    my $args = {
        type      => 'l2',  # l2 or l3
        bandwidth => 50,
        bgp_auth  => '',    # Empty or Null disables BGP Auth
        mtu       => 1500,  # MTU_1500 or MTU_9000
        oess_ip   => undef,
        peer_ip   => undef,
        oess_ipv6 => undef,
        peer_ipv6 => undef,
        vlan      => undef,
        @_
    };

    return {
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
    };
}

=head2 delete_virtual_circuit

=cut
sub delete_virtual_circuit {
    my $self = shift;
    my $id = shift;

    if ($id eq "UniqueVirtualCircuitId123") {
        return {
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
            }],
            "lifecycleState" => "TERMINATING",
            "providerState" => "ACTIVE",
            "bgpSessionState" => "UP",
            "region" => "IAD"
        };
    }

    if ($id eq "UniqueVirtualCircuitId456") {
        return {
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
        return {
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
}

return 1;
