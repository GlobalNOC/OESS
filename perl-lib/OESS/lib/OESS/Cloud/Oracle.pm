package OESS::Cloud::Oracle;

use strict;
use warnings;

use Data::Dumper;
use JSON::XS;
use Log::Log4perl;


=head1 OESS::Cloud::Oracle

    use OESS::Cloud::Oracle

=cut


=head2 new

    my $oracle = new OESS::Cloud::Oracle();

=cut
sub new {
    my $class = shift;
    my $args  = {
        config => "/etc/oess/database.xml",
        logger => Log::Log4perl->get_logger("OESS.Cloud.Oracle"),
        @_
    };
    my $self = bless $args, $class;

    return $self;
}

=head2 get_virtual_circuit

=cut
sub get_virtual_circuit {
    my $self = shift;

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
                "oracleBgpPeeringIp" => "10.0.0.19/31",
                "customerBgpPeeringIp" => "10.0.0.18/31",
            }],
            "lifecycleState" => "PENDING_PROVIDER",
            "providerState" => "INACTIVE",
            "bgpSessionState" => "DOWN",
            "region" => "IAD"
        }
    ];
    return ($results, undef);
}

=head2 update_virtual_circuit

=cut
sub update_virtual_circuit {
    my $self = shift;
    my $args = {
        ocid      => undef, # Oracle Cloud Identifier
        name      => '',    # User-friendly name. Not unique. Changeable. No confidential info.
        type      => 'l2',  # l2 or l3
        bandwidth => 50,    # Converted from int to something like 2Gbps
        auth_key  => '',    # Empty or Null disables BGP Auth
        mtu       => 1500,  # Coverted from int to MTU_1500 or MTU_9000
        oess_asn  => undef,
        oess_ip   => undef, # /31
        peer_ip   => undef, # /31
        oess_ipv6 => undef, # /127
        peer_ipv6 => undef, # /127
        vlan      => undef,
        @_
    };

    my $bandwidth;
    my $mtu;

    # TODO bandwidth and mtu must be converted to the proper ENUMs
    $bandwidth = $args->{bandwidth};
    $mtu = ($args->{mtu} == 1500) ? 'MTU_1500' : 'MTU_9000';

    my $l2_payload = {
        crossConnectMappings => [
            {
                crossConnectOrCrossConnectGroupId => $args->{ocid},
                vlan => $args->{vlan},
            }
        ],
        providerState => 'ACTIVE',
        bandwidthShapeName => $bandwidth,
        displayName => $args->{name} 
    };

    my $l3_payload = {
        crossConnectMappings => [
            {
                bgpMd5AuthKey => $args->{auth_key},
                crossConnectOrCrossConnectGroupId => $args->{ocid},
                customerBgpPeeringIp => $args->{oess_ip},
                oracleBgpPeeringIp => $args->{peer_ip},
                customerBgpPeeringIpv6 => $args->{oess_ipv6},
                oracleBgpPeeringIpv6 => $args->{peer_ipv6},
                vlan => $args->{vlan},
            }
        ],
        providerState => 'ACTIVE',
        bandwidthShapeName => $bandwidth,
        customerBgpAsn => $args->{oess_asn},
        displayName => $args->{name}, # A user-friendly name. Not unique and changeable. Avoid confidential information.
        ipMtu => $mtu
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
            "crossConnectOrCrossConnectGroupId" => "CrossConnect1",
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

return 1;
