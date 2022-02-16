package OESS::Cloud;

use strict;
use warnings;

use Exporter;
use Log::Log4perl;

use OESS::Cloud::AWS;
use OESS::Cloud::Azure;
use OESS::Cloud::AzurePeeringConfig;
use OESS::Cloud::GCP;
use OESS::Cloud::Oracle;
use OESS::Config;
use OESS::DB::Endpoint;

use Data::Dumper;
use Data::UUID;

=head1 OESS::Cloud

=cut

=head2 setup_endpoints

setup_endpoints configures cloud services for any interface in
C<$endpoints> with a configured cloud interconnect id. Once complete,
any information related to new cloud services is recorded in the
resulting endpoint list. The resulting endpoint list should be used as
a replacement for the parent VRF's endpoints.

    my $setup_endpoints = Cloud::setup_endpoints('vrf1', $vrf->endpoints, 123456789);
    $vrf->endpoints($setup_endpoints);
    $vrf->update_db();

=cut
sub setup_endpoints {
    my $db         = shift;
    my $vrf_id     = shift; # undef for l2conns
    my $vrf_name   = shift;
    my $endpoints  = shift; # OESS::Endpoint
    my $is_admin   = shift; # 1 or 0

    my $result     = [];

    my $config = OESS::Config->new();
    my $logger = Log::Log4perl->get_logger('OESS.Cloud');

    my $azure_connections = {};
    my $azure_peering_config = new OESS::Cloud::AzurePeeringConfig(db => $db);
    if (defined $vrf_id) {
        $azure_peering_config->load($vrf_id);
    }

    foreach my $ep (@$endpoints) {
        if (!$ep->cloud_interconnect_id) {
            push @$result, $ep;
            next;
        }

        if ($ep->cloud_interconnect_type eq 'aws-hosted-connection') {
            $logger->info("Adding cloud interconnect of type aws-hosted-connection.");
            my $aws = OESS::Cloud::AWS->new();

            my $res = $aws->allocate_connection(
                $ep->cloud_interconnect_id,
                $vrf_name,
                $ep->cloud_account_id,
                $ep->tag,
                $ep->bandwidth . 'Mbps'
            );
            $ep->cloud_account_id($ep->cloud_account_id);
            $ep->cloud_connection_id($res->{ConnectionId});
            push @$result, $ep;

        } elsif ($ep->cloud_interconnect_type eq 'aws-hosted-vinterface') {
            $logger->info("Adding cloud interconnect of type aws-hosted-vinterface.");
            my $aws = OESS::Cloud::AWS->new();

            my $amazon_addr   = undef;
            my $asn           = $config->local_as;
            my $auth_key      = undef;
            my $customer_addr = undef;
            my $ip_version    = 'ipv6';

            my $peer = $ep->peers()->[0];
            if (defined $peer) {
                $amazon_addr   = $peer->peer_ip;
                $auth_key      = $peer->md5_key;
                $customer_addr = $peer->local_ip;
                $ip_version    = $peer->ip_version;

                # AWS Auto-Generates IPv6 Addresses
                if ($ip_version != 'ipv4') {
                    $amazon_addr = undef;
                    $customer_addr = undef;
                }
            }

            my $res = $aws->allocate_vinterface(
                $ep->cloud_interconnect_id,
                $ep->cloud_account_id,
                $ip_version,
                $amazon_addr,
                $asn,
                $auth_key,
                $customer_addr,
                $vrf_name,
                $ep->tag,
                $ep->mtu
            );
            $ep->cloud_account_id($ep->cloud_account_id);
            $ep->cloud_connection_id($res->{VirtualInterfaceId});
            if (defined $peer) {
                $peer->peer_asn($res->{AmazonSideAsn});
            }
            push @$result, $ep;

        } elsif ($ep->cloud_interconnect_type eq 'gcp-partner-interconnect') {
            $logger->info("Adding cloud interconnect of type gcp-partner-interconnect.");
            my $gcp = OESS::Cloud::GCP->new();

            my $id_gen = Data::UUID->new;
            my $id_obj = $id_gen->create();
            my $uuid   = $id_gen->to_string($id_obj);

            # GCP attachment names ($connection_id) require that: the
            # first character must be a lowercase letter, and all
            # following characters must be a dash, lowercase letter,
            # or digit, except the last character, which cannot be a
            # dash. To meet these requirements 'a-' is appended to a
            # lowercase uuid.
            my $interconnect_name = $vrf_name;
            my $connection_id     = 'a-' . lc($uuid);

            my $max_gcp_bandwidth = 5000;
            if ($ep->bandwidth > $max_gcp_bandwidth) {
                die "The maximum bandwidth of GCP Partner Interconnects is currently restricted to $max_gcp_bandwidth Mbps.\n";
            }

            my $bandwidth = '';
            if ($ep->bandwidth >= 1000) {
                $bandwidth = 'BPS_' . ($ep->bandwidth / 1000) . 'G';
            } else {
                $bandwidth = 'BPS_' . $ep->bandwidth . 'M';
            }

            my $res = $gcp->insert_interconnect_attachment(
                interconnect_id   => $ep->cloud_interconnect_id,
                interconnect_name => $interconnect_name,
                bandwidth         => $bandwidth,
                connection_id     => $connection_id,
                pairing_key       => $ep->cloud_account_id,
                portal_url        => $config->base_url,
                vlan              => $ep->tag
            );

            $ep->cloud_connection_id($connection_id);
            push @$result, $ep;

        } elsif ($ep->cloud_interconnect_type eq 'azure-express-route') {
            $logger->info("Adding cloud interconnect of type azure-express-route.");

            if (defined $azure_connections->{$ep->cloud_account_id}) {
                my $conf = $azure_connections->{$ep->cloud_account_id};
                $ep->cloud_connection_id($conf->{id});
                $ep->tag($conf->{tag});
                $ep->inner_tag($conf->{inner_tag});
                push @$result, $ep;
                next;
            }

            my $azure = OESS::Cloud::Azure->new();

            # Configure peering information only on layer 3
            # connections.
            my $conn = $azure->expressRouteCrossConnection($ep->cloud_interconnect_id, $ep->cloud_account_id);
            my $peering = $azure_peering_config->cross_connection_peering($ep->cloud_account_id);

            # Validate that configured bandwidth reservation allowed
            my $ep_intf = new OESS::Interface(db => $ep->{db}, interface_id => $ep->interface_id);
            if (!$ep_intf->is_bandwidth_valid(bandwidth => $conn->{properties}->{bandwidthInMbps}, is_admin  => $is_admin)) {
                die "Bandwidth configured on Azure endpoint is not supported.";
            }

            my $res = $azure->set_cross_connection_state_to_provisioned(
                interconnect_id  => $ep->cloud_interconnect_id,
                service_key      => $ep->cloud_account_id,
                circuit_id       => $conn->{properties}->{expressRouteCircuit}->{id},
                region           => $conn->{location},
                peering_location => $conn->{properties}->{peeringLocation},
                bandwidth        => $conn->{properties}->{bandwidthInMbps},
                vlan             => $ep->tag,
                local_asn        => $config->local_as,
                peering          => $peering
            );

            $ep->cloud_connection_id($res->{id});
            $ep->inner_tag($ep->tag);
            $ep->tag($conn->{properties}->{sTag});
            $ep->bandwidth($conn->{properties}->{bandwidthInMbps});

            $azure_connections->{$ep->cloud_account_id} = {
                id        => $ep->cloud_connection_id,
                tag       => $ep->tag,
                inner_tag => $ep->inner_tag
            };

            push @$result, $ep;

        } elsif ($ep->cloud_interconnect_type eq 'oracle-fast-connect') {
            $logger->info("Adding cloud interconnect of type oracle-fast-connect.");
            my $oracle = new OESS::Cloud::Oracle();
            my $conn_type = 'l2';
            my $auth_key = '';
            my $oess_ip = undef;
            my $peer_ip = undef;
            my $oess_ipv6 = undef;
            my $peer_ipv6 = undef;

            # Layer3 Connection Check
            if (defined $ep->vrf_endpoint_id) {
                $conn_type = 'l3';
                foreach my $peer (@{$ep->peers}) {
                    # Auth key is assumed to be the same for all peers on a
                    # given endpoint.
                    $auth_key = (defined $peer->md5_key) ? $peer->md5_key : '';

                    if ($peer->ip_version eq 'ipv4') {
                        $oess_ip = $peer->local_ip;
                        $peer_ip = $peer->peer_ip;
                    } else {
                        $oess_ipv6 = $peer->local_ip;
                        $peer_ipv6 = $peer->peer_ip;
                    }
                }
            }

            my $res = $oracle->update_virtual_circuit(
                ocid      => $ep->cloud_account_id,
                name      => $vrf_name,
                type      => $conn_type,
                bandwidth => $ep->bandwidth,
                auth_key  => $auth_key,
                mtu       => $ep->mtu,
                oess_asn  => $config->local_as,
                oess_ip   => $oess_ip,
                peer_ip   => $peer_ip,
                oess_ipv6 => $oess_ipv6,
                peer_ipv6 => $oess_ipv6,
                vlan      => $ep->tag
            );

            $ep->cloud_connection_id($res->{id});

            push @$result, $ep;
        } else {
            $logger->warn("Cloud interconnect type is not supported.");
        }
    }

    return $result;
}

=head2 cleanup_endpoints

cleanup_endpoints removes cloud services for any interface in
C<$endpoints> with a configured cloud interconnect id.

    my $ok = Cloud::cleanup_endpoints($vrf->endpoints);

=cut
sub cleanup_endpoints {
    my $endpoints = shift;

    my $config = OESS::Config->new();
    my $logger = Log::Log4perl->get_logger('OESS.Cloud');

    my $conn_azure_endpoint_count = {};
    foreach my $ep (@$endpoints) {
        if ($ep->cloud_interconnect_type eq 'azure-express-route') {
            # Get number of Endpoints using the provided azure service
            # key. If cloud_account_id is in use on another endpoint
            # we'll want to wait before deprovisioning the
            # ExpressRoute.
            if (!defined $conn_azure_endpoint_count->{$ep->cloud_account_id}) {
                $conn_azure_endpoint_count->{$ep->cloud_account_id} = 0;
            }
            $conn_azure_endpoint_count->{$ep->cloud_account_id} += 1;
        }
    }

    foreach my $ep (@$endpoints) {
        if (!$ep->cloud_interconnect_id) {
            next;
        }

        if ($ep->cloud_interconnect_type eq 'aws-hosted-connection') {
            my $aws = OESS::Cloud::AWS->new();

            my $aws_account = $ep->cloud_account_id;
            my $aws_connection = $ep->cloud_connection_id;
            if (!defined $aws_connection || $aws_connection eq '') {
                next;
            }

            $logger->info("Removing aws-hosted-connection $aws_connection from $aws_account.");
            $aws->delete_connection($ep->cloud_interconnect_id, $aws_connection);

        } elsif ($ep->cloud_interconnect_type eq 'aws-hosted-vinterface') {
            my $aws = OESS::Cloud::AWS->new();

            my $aws_account = $ep->cloud_account_id;
            my $aws_connection = $ep->cloud_connection_id;
            if (!defined $aws_connection || $aws_connection eq '') {
                next;
            }

            $logger->info("Removing aws-hosted-vinterface $aws_connection from $aws_account.");
            $aws->delete_vinterface($ep->cloud_interconnect_id, $aws_connection);

        } elsif ($ep->cloud_interconnect_type eq 'gcp-partner-interconnect') {
            my $gcp = OESS::Cloud::GCP->new();

            my $interconnect_id = $ep->cloud_interconnect_id;
            my $connection_id = $ep->cloud_connection_id;
            my $pairing_key = $ep->cloud_account_id;
            if (!defined $connection_id || $connection_id eq '') {
                next;
            }

            $logger->info("Removing gcp-partner-interconnect $connection_id from $interconnect_id.");
            my $res = $gcp->delete_interconnect_attachment(
                interconnect_id => $interconnect_id,
                connection_id => $connection_id,
                pairing_key => $pairing_key
            );

        } elsif ($ep->cloud_interconnect_type eq 'azure-express-route') {
            my $azure = OESS::Cloud::Azure->new();

            my $interconnect_id = $ep->cloud_interconnect_id;
            my $service_key = $ep->cloud_account_id;

            my ($eps, $eps_err) = OESS::DB::Endpoint::fetch_all(db => $ep->{db}, cloud_account_id => $ep->cloud_account_id);
            if (defined $eps_err) {
                $logger->error($eps_err);
                next;
            }
            my $full_azure_endpoint_count = (defined $eps) ? scalar @$eps : 0;
            my $diff_azure_endpoint_count = $full_azure_endpoint_count - $conn_azure_endpoint_count->{$ep->cloud_account_id};

            if ($diff_azure_endpoint_count > 0) {
                $logger->info("Not removing azure-express-route: $service_key is in use by another Connection.");
                next;
            }

            $logger->info("Removing azure-express-route $service_key from $interconnect_id.");
            my $conn = $azure->expressRouteCrossConnection($interconnect_id, $service_key);
            my $res = $azure->set_cross_connection_state_to_not_provisioned(
                interconnect_id  => $interconnect_id,
                service_key      => $service_key,
                circuit_id       => $conn->{properties}->{expressRouteCircuit}->{id},
                region           => $conn->{location},
                peering_location => $conn->{properties}->{peeringLocation},
                bandwidth        => $conn->{properties}->{bandwidthInMbps},
                vlan             => $ep->tag
            );

        } elsif ($ep->cloud_interconnect_type eq 'oracle-fast-connect') {
            my $oracle = new OESS::Cloud::Oracle();

            my $interconnect_id = $ep->cloud_interconnect_id;
            my $connection_id = $ep->cloud_connection_id;

            $logger->info("Removing oracle-fast-connect $connection_id from $interconnect_id.");
            my $res = $oracle->delete_virtual_circuit($connection_id);

        } else {
            $logger->warn("Cloud interconnect type is not supported.");
        }
    }

    return 1;
}

return 1;
