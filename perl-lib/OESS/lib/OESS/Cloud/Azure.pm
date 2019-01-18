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
for GCP connections are C<azure-express-route>.

    <!-- azure-express-route -->
    <connection region="us-east"
                interconnect_type="azure-express-route"
                interconnect_id=""
                client_id="00000000-0000-0000-0000-000000000000"
                client_secret="..."
                tenant_id="00000000-0000-0000-0000-000000000000"
                workgroup="Azure" />

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
    # $self->{connections} = {};
    $self->{connection} = {};

    foreach my $conn (@{$self->{creds}->{cloud}->{connection}}) {
        if ($conn->{interconnect_type} ne 'azure-express-route') {
            next;
        }
        # $self->{connections}->{$conn->{interconnect_id}} = $conn;
        $self->{connection} = $conn;

        my $client_id = $conn->{client_id};
        my $client_secret = $conn->{client_secret};
        my $tenant_id = $conn->{tenant_id};

        my $ua = LWP::UserAgent->new();
        my $response = $ua->post(
          "https://login.microsoftonline.com/$tenant_id/oauth2/token",
          {
              grant_type => 'client_credentials',
              client_id => $client_id,
              client_secret => $client_secret,
              resource => 'https://management.azure.com/'
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

        # $self->{connections}->{$conn->{interconnect_id}} = $conn;
        $self->{connection} = $conn;
    }

    return $self;
}

sub subscriptions {
    my $self = shift;

    my $http = $self->{connection}->{http};

    my $api_response = $http->get("https://management.azure.com/subscriptions/?api-version=2018-11-01");

    my $api_data = decode_json($api_response->content);
    return $api_data->{value};
}


# Microsoft.Network
sub expressRouteCrossConnections {
    my $self = shift;
    my $sub_id = shift;

    my $http = $self->{connection}->{http};

    my $api_response = $http->get(
        "https://management.azure.com/subscriptions/$sub_id/providers/Microsoft.Network/expressRouteCrossConnections/?api-version=2018-12-01"
    );

    my $api_data = decode_json($api_response->content);
    return $api_data;
}


sub expressRouteCrossConnection {
    my $self = shift;
    my $id = shift;

    my $http = $self->{connection}->{http};
    my $resp = $http->get("https://management.azure.com/$id?api-version=2018-08-01");
    return decode_json($resp->content);
}


sub add_peering {
    my $self = shift;
    my $id = shift;         # CrossConnectionId

    my $payload = {
        properties => {
            peerASN => 3,
            peeringType => 'AzurePrivatePeering',
#            primaryPeerAddressPrefix => '192.168.16.252/30',
#            secondaryPeerAddressPrefix => '192.168.18.252/30',
            vlanId => 2032,
            ipv6PeeringConfig => {
                primaryPeerAddressPrefix => "3FFE:FFFF:0:CD30::/126",
                secondaryPeerAddressPrefix => "3FFE:FFFF:0:CD30::4/126"
            }
        }
    };

    my $req = HTTP::Request->new("PUT", "https://management.azure.com$id/peerings/AzurePrivatePeering?api-version=2018-12-01");
    $req->header("Content-Type" => "application/json");
    $req->content(encode_json($payload));

    my $http = $self->{connection}->{http};
    my $resp = $http->request($req);
    return decode_json($resp->content);
}

sub delete_peering {
    my $self = shift;
    my $peering_id = shift;
    my $req = HTTP::Request->new("DELETE", "https://management.azure.com$peering_id/peerings/AzurePrivatePeering?api-version=2018-08-01");
    $req->header("Content-Type" => "application/json");

    my $http = $self->{connection}->{http};
    my $resp = $http->request($req);
    return decode_json($resp->content);
}


sub set_cross_connection_state_to_provisioning {
    my $self = shift;
    my $id = shift;         # CrossConnectionId
    my $circuit_id = shift; # CircuitId

    my $payload = {
        id => $id,
        properties => {
            bandwidthInMbps => 50,
            serviceProviderProvisioningState => 'Provisioning',
            peeringLocation => 'Silicon Valley Test',
            expressRouteCircuit => { id => $circuit_id },
            peerings => [
                {
                    name => 'AzurePrivatePeering',
                    properties => {
                        peerASN => 3,
                        primaryPeerAddressPrefix => '192.168.16.252/30',
                        secondaryPeerAddressPrefix => '192.168.18.252/30',
                        vlanId => 2032,
                        ipv6PeeringConfig => {
                            primaryPeerAddressPrefix => "3FFE:FFFF:0:CD30::/126",
                            secondaryPeerAddressPrefix => "3FFE:FFFF:0:CD30::4/126"
                        }
                    }
                }
            ]
        },
        location => 'westus'
    };

    my $req = HTTP::Request->new("PUT", "https://management.azure.com/$id?api-version=2018-12-01");
    $req->header("Content-Type" => "application/json");
    $req->content(encode_json($payload));

    my $http = $self->{connection}->{http};
    my $resp = $http->request($req);

    return decode_json($resp->content);
}

sub set_cross_connection_state_to_provisioned {
    my $self = shift;
    my $id = shift;         # CrossConnectionId
    my $circuit_id = shift; # CircuitId

    my $payload = {
        id => $id,
        properties => {
            bandwidthInMbps => 50,
            serviceProviderProvisioningState => 'Provisioned',
            peeringLocation => 'Silicon Valley Test',
            expressRouteCircuit => { id => $circuit_id }
        },
        location => 'westus'
    };

    my $req = HTTP::Request->new("PUT", "https://management.azure.com/$id?api-version=2018-12-01");
    $req->header("Content-Type" => "application/json");
    $req->content(encode_json($payload));

    my $http = $self->{connection}->{http};
    my $resp = $http->request($req);

    return decode_json($resp->content);
}

sub updateExpressRouteCrossConnectionState {
    my $self = shift;
    my $id = shift;         # CrossConnectionId
    my $circuit_id = shift; # CircuitId
    my $state = shift;

    my $payload = {
        id => $id,
        properties => {
            bandwidthInMbps => 50,
            serviceProviderProvisioningState => $state,
            peeringLocation => 'Silicon Valley Test',
            expressRouteCircuit => { id => $circuit_id },
            peerings => [
                {
                    name => 'AzurePrivatePeering',
                    properties => {
                        peerASN => 3,
                        primaryPeerAddressPrefix => '192.168.16.252/30',
                        secondaryPeerAddressPrefix => '192.168.18.252/30',
                        vlanId => 2032
                        # ipv6PeeringConfig => {
                        #     primaryPeerAddressPrefix => "3FFE:FFFF:0:CD30::/126",
                        #     secondaryPeerAddressPrefix => "3FFE:FFFF:0:CD30::4/126",
                        #     state => 'Enabled'
                        # }
                    }
                }
            ]
        },
        location => 'westus'
    };

    my $req = HTTP::Request->new("PUT", "https://management.azure.com/$id?api-version=2018-12-01");
    $req->header("Content-Type" => "application/json");
    $req->content(encode_json($payload));

    my $http = $self->{connection}->{http};
    my $resp = $http->request($req);

    return decode_json($resp->content);
}

sub microsoftNetworkResources {
    my $self = shift;
    my $sub_id = shift;

    my $http = $self->{connection}->{http};

    my $api_response = $http->get(
        "https://management.azure.com/subscriptions/$sub_id/providers/Microsoft.Network/?api-version=2018-11-01"
    );

    my $api_data = decode_json($api_response->content);
    return $api_data;
}


return 1;
