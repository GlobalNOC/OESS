package OESS::Cloud::Azure;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Log::Log4perl;
use LWP::UserAgent;
use XML::Simple;

=head1 OESS::Cloud::Azure

B<Configuration:>

The credentials for each interconnect must be defined under the
C<cloud> tag in C</etc/oess/database.xml>. Valid interconnect types
for Azure connections are C<azure-express-route>.

The C<interconnect_id> should be the name of the associated Azure port
that represents the physical connection. Listed under the provider
subscription's Resource groups.

C<subscription_id> is the Azure Subscription ID of the provider's
account as shown under Subscriptions.

C<client_id> is the Azure Application (client) ID as shown under App
registrations (Preview).

C<client_secret> is the Azure Client Secrets ID as shown under App
registrations (Preview) > Certificates & secrets.

C<tenant_id> is the Azure Directory (tenant) ID as shown under App
registrations (Preview). There should be just one per organization.

    <!-- azure-express-route -->
    <connection client_id="00000000-0000-0000-0000-000000000000"
                client_secret="..."
                interconnect_type="azure-express-route"
                interconnect_id="ProviderTest-SJC-TEST-06GMR-CIS-1-PRI-A"
                region="us-east"
                resource_group="CrossConnection-SiliconValleyTest"
                subscription_id="00000000-0000-0000-0000-000000000000"
                tenant_id="00000000-0000-0000-0000-000000000000"
                workgroup="Azure" />

B<Errors:>

Web errors are returned in the following format.

    {
        'error' => {
            'details' => [{
                'message' => 'Error converting value ..., line 1, position 549.',
                'code' => 'InvalidJson'
            }],
            'message' => 'Cannot parse the request.',
            'code' => 'InvalidRequestFormat'
        }
    };


=cut

=head2 new

    my $azure = OESS::Cloud::Azure->new();

=cut
sub new {
    my $class = shift;
    my $args  = {
        config => '/etc/oess/database.xml',
        logger => Log::Log4perl->get_logger('OESS.Cloud.Azure'),
        @_
    };
    my $self = bless $args, $class;

    $self->{creds} = XML::Simple::XMLin($self->{config});
    $self->{base_url} = {};
    $self->{connections} = {};
    $self->{resource_groups} = {};

    foreach my $conn (@{$self->{creds}->{cloud}->{connection}}) {
        if ($conn->{interconnect_type} ne 'azure-express-route') {
            next;
        }

        my $client_id       = $conn->{client_id};
        my $client_secret   = $conn->{client_secret};
        my $interconnect_id = $conn->{interconnect_id};
        my $subscription_id = $conn->{subscription_id};
        my $tenant_id       = $conn->{tenant_id};
        my $base_url        = $conn->{base_url} || 'https://management.azure.com';
        my $auth_url        = $conn->{auth_url} || "https://login.microsoftonline.com";

        my $ua = LWP::UserAgent->new();
        my $response = $ua->post(
          "$auth_url/$tenant_id/oauth2/token",
          {
              grant_type => 'client_credentials',
              client_id => $client_id,
              client_secret => $client_secret,
              resource => "$base_url/"
          }
        );
        if (!$response->is_success) {
            $self->{logger}->error($response->content);
            warn Dumper($response->content);
            next;
        }

        my $data = decode_json($response->content);
        $conn->{access_token} = $data->{access_token};

        $conn->{http} = LWP::UserAgent->new();
        $conn->{http}->default_header(Authorization => "Bearer $conn->{access_token}");

        $self->{connections}->{$conn->{interconnect_id}} = $conn;
        $self->{resource_groups}->{$conn->{interconnect_id}} = $conn->{resource_group};
        $self->{base_url}->{$conn->{interconnect_id}} = $base_url;
    }

    return $self;
}

=head2 resourceGroups

    my $interconnects = $azure->resourceGroups($interconnect_id);

resourceGroups returns a list of all ResourceGroups associated with
this interconnect's subscription_id. Each resource group represents a
physical connection (interconnect) to Azure, and its C<name> may be
used as an C<interconnect_id> with this object's methods.

Note: Just because an interconnect is listed in this response doesn't
mean that it has also been configured in oess. See above for
interconnect configuration info.

=cut
sub resourceGroups {
    my $self = shift;
    my $interconnect_id = shift;

    my $conn = $self->{connections}->{$interconnect_id};
    my $sub  = $conn->{subscription_id};
    my $base_url = $self->{base_url}->{$interconnect_id};

    my $http = $self->{connection}->{http};

    my $api_response = $conn->{http}->get(
        "$base_url/subscriptions/$sub/resourceGroups?api-version=2014-04-01"
    );

    my $api_data = decode_json($api_response->content);
    return $api_data->{value};
}

=head2 expressRouteCrossConnections

    my $cross_connections = $azure->resourceGroups($interconnect_id);

expressRouteCrossConnections returns a list of all ExpressRoute
CrossConnections on interconnect C<$interconnect_id>. The C<name> of
each CrossConnection is its ServiceKey.

The results of this method will B<not> include configured peeringings.

=cut
sub expressRouteCrossConnections {
    my $self = shift;
    my $interconnect_id = shift;

    my $conn = $self->{connections}->{$interconnect_id};
    my $sub  = $conn->{subscription_id};
    my $group = $conn->{resource_group};
    my $base_url = $self->{base_url}->{$interconnect_id};

    my $api_response = $conn->{http}->get(
        "$base_url/subscriptions/$sub/resourceGroups/$group/providers/Microsoft.Network/expressRouteCrossConnections/?api-version=2018-12-01"
    );

    my $api_data = decode_json($api_response->content);
    return $api_data->{value};
}

=head2 expressRouteCrossConnection

    my $cross_connection = $azure->expressRouteCrossConnection($interconnect_id, $service_key);

expressRouteCrossConnection returns the ExpressRoute on interconnect
C<$interconnect_id> identified by C<$service_key> (oess'
C<cloud_account_id>). Use this method to retrieve the CrossConnection's
peerings.

=cut
sub expressRouteCrossConnection {
    my $self            = shift;
    my $interconnect_id = shift;
    my $service_key     = shift;

    my $conn = $self->{connections}->{$interconnect_id};
    my $sub = $conn->{subscription_id};
    my $group = $conn->{resource_group};
    my $base_url = $self->{base_url}->{$interconnect_id};

    my $resp = $conn->{http}->get(
        "$base_url/subscriptions/$sub/resourceGroups/$group/providers/Microsoft.Network/expressRouteCrossConnections/$service_key?api-version=2018-12-01"
    );
    return decode_json($resp->content);
}

=head2 set_cross_connection_state_to_provisioned

    my $conn = $azure->expressRouteCrossConnection($interconnect_id, $service_key);
    
    my $res = $azure->set_cross_connection_state_to_provisioned(
        interconnect_id  => $interconnect_id,
        service_key      => $service_key,
        circuit_id       => $conn->{properties}->{expressRouteCircuit}->{id},
        region           => $conn->{location},
        peering_location => $conn->{properties}->{peeringLocation},
        bandwidth        => $conn->{properties}->{bandwidthInMbps},
        vlan             => $vlan,
        local_asn        => $asn,
        primary_prefix   => $slash30_a,
        secondary_prefix => $slash30_b
    );

set_cross_connection_state_to_provisioned sets the
C<serviceProviderProvisioningState> to C<'Provisioned'> on the
ExpressRoute defined by C<id> and C<circuit_id>. It additionally
creates an ipv4 peering on the specified C<vlan>.

=cut
sub set_cross_connection_state_to_provisioned {
    my $self = shift;
    my $args = {
        interconnect_id  => undef,
        service_key      => undef,
        circuit_id       => undef,
        region           => undef,
        peering_location => undef,
        bandwidth        => undef,
        vlan             => undef,
        local_asn        => undef,
        peering          => undef,
        @_
    };

    my $conn = $self->{connections}->{$args->{interconnect_id}};
    my $sub = $conn->{subscription_id};
    my $group = $conn->{resource_group};
    my $base_url = $self->{base_url}->{$args->{interconnect_id}};

    my $url = "$base_url/subscriptions/$sub/resourceGroups/$group/providers/Microsoft.Network/expressRouteCrossConnections/$args->{service_key}?api-version=2018-12-01";

    my $payload = {
        id         => "/subscriptions/$sub/resourceGroups/$group/providers/Microsoft.Network/expressRouteCrossConnections/$args->{service_key}",
        location   => $args->{region},
        properties => {
            bandwidthInMbps                  => $args->{bandwidth},
            expressRouteCircuit              => { id => $args->{circuit_id} },
            peeringLocation                  => $args->{peering_location},
            # peerings                         => undef, Historically not included
            serviceProviderProvisioningState => 'Provisioned',
        }
    };

    if (defined $args->{peering}) {
        my $peering_properties = $args->{peering};
        $peering_properties->{peerASN} = $args->{local_asn};
        $peering_properties->{vlanId}  = $args->{vlan};

        $payload->{properties}->{peerings} = [{
                name       => 'AzurePrivatePeering',
                properties => $peering_properties
        }];
    }

    my $req = HTTP::Request->new("PUT", $url);
    $req->header("Content-Type" => "application/json");
    $req->content(encode_json($payload));

    my $resp = $conn->{http}->request($req);
    if (defined $resp->{error}) {
        foreach my $detail (@{$resp->{error}->{details}}) {
            $self->{logger}->error($detail->{message});
            return;
        }
    }

    return decode_json($resp->content);
}

=head2 set_cross_connection_state_to_not_provisioned

    my $conn = $azure->expressRouteCrossConnection($interconnect_id, $service_key);
    
    my $res = $azure->set_cross_connection_state_to_not_provisioned(
        interconnect_id  => $interconnect_id,
        service_key      => $service_key,
        circuit_id       => $conn->{properties}->{expressRouteCircuit}->{id},
        region           => $conn->{location},
        peering_location => $conn->{properties}->{peeringLocation},
        bandwidth        => $conn->{properties}->{bandwidthInMbps}
    );

set_cross_connection_state_to_not_provisioned sets the
C<serviceProviderProvisioningState> to C<'NotProvisioned'> on the
ExpressRoute defined by C<id> and C<circuit_id>. Additionally, it
removes any existing ipv4 peerings.

=cut
sub set_cross_connection_state_to_not_provisioned {
    my $self = shift;
    my $args = {
        interconnect_id  => undef,
        service_key      => undef,
        circuit_id       => undef,
        region           => undef,
        peering_location => undef,
        bandwidth        => undef,
        @_
    };

    my $conn = $self->{connections}->{$args->{interconnect_id}};
    my $sub = $conn->{subscription_id};
    my $group = $conn->{resource_group};
    my $base_url = $self->{base_url}->{$args->{interconnect_id}};

    my $url = "$base_url/subscriptions/$sub/resourceGroups/$group/providers/Microsoft.Network/expressRouteCrossConnections/$args->{service_key}?api-version=2018-12-01";

    my $payload = {
        id => "/subscriptions/$sub/resourceGroups/$group/providers/Microsoft.Network/expressRouteCrossConnections/$args->{service_key}",
        properties => {
            bandwidthInMbps => $args->{bandwidth},
            serviceProviderProvisioningState => 'NotProvisioned',
            peeringLocation => $args->{peering_location},
            expressRouteCircuit => { id => $args->{circuit_id} },
            peerings => []
        },
        location => $args->{region}
    };

    my $req = HTTP::Request->new("PUT", $url);
    $req->header("Content-Type" => "application/json");
    $req->content(encode_json($payload));

    my $resp = $conn->{http}->request($req);
    if (defined $resp->{error}) {
        foreach my $detail (@{$resp->{error}->{details}}) {
            $self->{logger}->error($detail->{message});
            return;
        }
    }

    return decode_json($resp->content);
}

=head2 get_port_sibling

     my $sibling = get_port_sibling('Internet2Test-AAA-AAAA-06AAA-AAA-1-PRI-A');

get_azure_port_sibling returns the name of C<$interconnect_id>'s
sibling port. Sibling is determined by the interconnect's
resource_group as defined in the oess config.

=cut
sub get_port_sibling {
    my $self = shift;
    my $interconnect_id = shift;

    my $resource_group = $self->{connections}->{$interconnect_id}->{resource_group};
    foreach my $key (keys %{$self->{connections}}) {
        if ($key eq $interconnect_id) {
            next;
        }

        my $v = $self->{connections}->{$key};
        if ($v->{resource_group} eq $resource_group) {
            return $v->{interconnect_id};
        }
    }

    return undef;
}

=head2 subscriptions

=cut
sub subscriptions {
    my $self = shift;
    my $interconnect_id = shift;

    my $conn = $self->{connections}->{$interconnect_id};
    my $base_url = $self->{base_url}->{$interconnect_id};

    my $api_response = $conn->{http}->get("$base_url/subscriptions/?api-version=2018-11-01");

    my $api_data = decode_json($api_response->content);
    return $api_data->{value};
}

=head2 expressRouteSimpleGet

=cut
sub expressRouteSimpleGet {
    my $self = shift;
    my $interconnect_id = shift;
    my $path = shift;

    my $conn = $self->{connections}->{$interconnect_id};
    my $base_url = $self->{base_url}->{$interconnect_id};

    my $resp = $conn->{http}->get("$base_url/$path?api-version=2018-08-01");
    return decode_json($resp->content);
}

=head2 allExpressRouteCrossConnections

=cut
sub allExpressRouteCrossConnections {
    my $self = shift;
    my $interconnect_id = shift;

    my $conn = $self->{connections}->{$interconnect_id};
    my $sub  = $conn->{subscription_id};
    my $base_url = $self->{base_url}->{$interconnect_id};

    my $api_response = $conn->{http}->get(
        "$base_url/subscriptions/$sub/providers/Microsoft.Network/expressRouteCrossConnections/?api-version=2018-12-01"
    );

    my $api_data = decode_json($api_response->content);
    return $api_data;
}

=head2 get_cross_connection_by_id

    my ($conn, $err) = get_cross_connection_by_id($interconnect_id, $service_key);
    die $err if defined $err;

get_cross_connection_by_id gets an Azure CrossConnection by Service
Key. The C<interconnect_id> is required to lookup the correct Azure
ResourceGroup and auth'd web client.

The result includes C<properties.primaryAzurePort> and
C<properties.secondaryAzurePort>. These may be used to lookup the
physical connections associated with the ExpressRoute Circuit.

=cut
sub get_cross_connection_by_id {
    my $self = shift;
    my $interconnect_id = shift;
    my $service_key = shift;

    my $conn = $self->{connections}->{$interconnect_id};
    my $sub  = $conn->{subscription_id};
    my $resource_group = $self->{resource_groups}->{$interconnect_id};
    my $base_url = $self->{base_url}->{$interconnect_id};

    my $api_response = $conn->{http}->get(
        "$base_url/subscriptions/$sub/resourceGroups/$resource_group/providers/Microsoft.Network/expressRouteCrossConnections/$service_key?api-version=2018-12-01"
    );
    my $api_data = decode_json($api_response->content);
    if (defined $api_data->{error}) {
        return (undef, $api_data->{error}->{message});
    }
    return ($api_data, undef);
}

return 1;
