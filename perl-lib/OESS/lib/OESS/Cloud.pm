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

    use OESS::Cloud

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

    # If an Oracle connection is in the 'provisioning' state modifications to
    # the connection are not possilbe and will result in an error. This means
    # that when adding For this
    # We can only call the provisioning method once when adding multiple
    # endpoints at the same time.
    my $oracle_connections = {};

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
                die "Bandwidth configured via Azure portal is not supported by OESS.";
            }
            if ($ep->bandwidth != $conn->{properties}->{bandwidthInMbps}) {
                die "Bandwidth set on Azure endpoint must match the bandwidth configured via Azure Portal.";
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
            if (!defined $oracle_connections->{$ep->cloud_account_id}) {
                $oracle_connections->{$ep->cloud_account_id} = [];
            }
            push @{$oracle_connections->{$ep->cloud_account_id}}, $ep;

        } else {
            $logger->warn("Cloud interconnect type is not supported.");
        }
    }

    # BEGIN Oracle specific logic
    foreach my $ocid (keys %$oracle_connections) {
        $logger->info("Adding cloud interconnect of type oracle-fast-connect.");
        my $cloud_interconnect_id;
        foreach my $ep (@{$oracle_connections->{$ocid}}) {
            $cloud_interconnect_id = $ep->cloud_interconnect_id;
        }

        my $oracle = new OESS::Cloud::Oracle(
            config_obj => $config,
            interconnect_id => $cloud_interconnect_id
        );

        my ($circuit, $err) = $oracle->get_virtual_circuit($ocid);
        die $err if defined $err;

        if (@{$circuit->{crossConnectMappings}} > 1) {
            die "An Oracle virtual circuit supports a maximum of two endpoints.";
        }

        my $bandwidth = 0;
        my $bfd = 0;
        my $conn_type = 'l3';
        my $cross_connect_mappings = [];
        my $mtu = 1500;

        foreach my $ccm (@{$circuit->{crossConnectMappings}}) {
            if (!defined $ccm->{crossConnectOrCrossConnectGroupId}) {
                # This should only happen for layer2 connections. Customers
                # define their BGP addresses on the oracle side at the same
                # time that they create their virtualCircuit, so those
                # values are stored in a crossConnectMapping.
                # 
                # There doesn't appear to be support for multiple
                # crossConnectMappings on a single l2 virtualCircut (this
                # makes sense), so if we completely ignore this
                # crossConnectMapping the info in the l2
                # crossConnectMapping that we create will be merged with
                # with the existing crossConnectMapping automatically; As
                # such we completely ignore this crossConnectMapping.
                next;
            }

            push @$cross_connect_mappings, {
                auth_key  => $ccm->{bgpMd5AuthKey}, # Not passed if empty string or undef
                bfd       => $circuit->{isBfdEnabled},
                ocid      => $ccm->{crossConnectOrCrossConnectGroupId}, # OCID of physical cross-connect or cross-connect-group. An OESS cloud_interconnect_id
                oess_ip   => $ccm->{customerBgpPeeringIp}, # /31
                peer_ip   => $ccm->{oracleBgpPeeringIp}, # /31
                oess_ipv6 => $ccm->{customerBgpPeeringIpv6}, # /127
                peer_ipv6 => $ccm->{oracleBgpPeeringIpv6}, # /127
                vlan      => $ccm->{vlan},
            };
        }

        foreach my $ep (@{$oracle_connections->{$ocid}}) {
            foreach my $ccm (@{$circuit->{crossConnectMappings}}) {
                if ($ep->cloud_interconnect_id eq $ccm->{crossConnectOrCrossConnectGroupId}) {
                    die "This Oracle virtual circuit already terminates on the specified port.";
                }
            }

            $bandwidth = $ep->bandwidth;
            $conn_type = ($circuit->{serviceType} eq 'LAYER2') ? 'l2' : 'l3';
            $mtu = $ep->mtu;

            my $ccm = {
                auth_key  => undef,
                ocid      => $ep->cloud_interconnect_id,
                oess_ip   => undef,
                peer_ip   => undef,
                oess_ipv6 => undef,
                peer_ipv6 => undef,
                vlan      => $ep->tag,
            };

            # Populate peering info if this is an l3connection
            if ($conn_type eq 'l3') {
                foreach my $peer (@{$ep->peers}) {
                    # Assume auth key is the same for all peers on an endpoint
                    $ccm->{auth_key} = (defined $peer->md5_key && $peer->md5_key ne '') ? $peer->md5_key : undef;
                    # Assume bfd is the same for all peers on an endpoint
                    $bfd = (defined $peer->bfd) ? $peer->bfd : 0;

                    if ($peer->ip_version eq 'ipv4') {
                        $ccm->{oess_ip} = $peer->local_ip;
                        $ccm->{peer_ip} = $peer->peer_ip;
                    } else {
                        $ccm->{oess_ipv6} = $peer->local_ip;
                        $ccm->{peer_ipv6} = $peer->peer_ip;
                    }
                }
            }
            push @$cross_connect_mappings, $ccm;
        }

        my ($update_res, $update_err) = $oracle->update_virtual_circuit(
            virtual_circuit_id     => $ocid,
            bandwidth              => $bandwidth,
            bfd                    => $bfd,
            mtu                    => $mtu,
            oess_asn               => $config->local_as,
            name                   => $vrf_name,
            type                   => $conn_type,
            cross_connect_mappings => $cross_connect_mappings
        );
        die $update_err if defined $update_err;

        foreach my $ep (@{$oracle_connections->{$ocid}}) {
            $ep->cloud_connection_id($update_res->{id});
            push @$result, $ep;
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

    # A request to delete Azure CrossConnections and Oracle
    # VirtualCircuits should only be made once per connection. Track
    # requests made with $removed_cloud_account_ids.
    my $removed_cloud_account_ids = {};

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

            next if defined $removed_cloud_account_ids->{$service_key};

            my ($eps, $eps_err) = OESS::DB::Endpoint::fetch_all(db => $ep->{db}, cloud_account_id => $service_key);
            if (defined $eps_err) {
                $logger->error($eps_err);
                next;
            }
            if (@$eps > 0) {
                $logger->info("Not removing azure-express-route $service_key from $interconnect_id. It's being used by another endpoint.");
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

            $removed_cloud_account_ids->{$service_key} = 1;
        } elsif ($ep->cloud_interconnect_type eq 'oracle-fast-connect') {
            my $oracle = new OESS::Cloud::Oracle(
                config_obj => $config,
                interconnect_id => $ep->cloud_interconnect_id
            );

            my $interconnect_id = $ep->cloud_interconnect_id;
            my $connection_id = $ep->cloud_account_id;

            next if defined $removed_cloud_account_ids->{$connection_id};

            my ($eps, $eps_err) = OESS::DB::Endpoint::fetch_all(db => $ep->{db}, cloud_account_id => $connection_id);
            if (defined $eps_err) {
                $logger->error($eps_err);
                next;
            }
            if (@$eps > 0) {
                $logger->info("Not removing oracle-fast-connect $connection_id from $interconnect_id. It's being used by another endpoint.");
                next;
            }

            $logger->info("Removing oracle-fast-connect $connection_id from $interconnect_id.");
            my ($res, $err) = $oracle->delete_virtual_circuit($connection_id);
            die $err if defined $err;

            $removed_cloud_account_ids->{$connection_id} = 1;
        } else {
            $logger->warn("Cloud interconnect type is not supported.");
        }
    }

    return 1;
}

return 1;
