#!/usr/bin/perl

# cron script for syncing cloud connection bandwidth

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Log::Log4perl;
use XML::Simple;


use OESS::DB;
use OESS::Cloud::Azure;
use OESS::Cloud::AzureSyncer;
use OESS::Config;


Log::Log4perl::init_and_watch('/etc/oess/logging.conf',10);
my $logger = Log::Log4perl->get_logger('OESS.Cloud.Azure.Syncer');


sub main {
    my $config_path = "/etc/oess/database.xml";
    my $db = new OESS::DB(config => $config_path);

    my $syncer = new OESS::Cloud::AzureSyncer(
        config => new OESS::Config(config_filename => $config_path),
        azure  => new OESS::Cloud::Azure(config => $config_path)
    );

    my ($endpoints, $err) = $syncer->fetch_azure_endpoints_from_oess();
    die $err if defined $err;

    my ($conns, $azure_err) = $syncer->fetch_cross_connections_from_azure();
    die $azure_err if defined $azure_err;
    warn Dumper($conns);

    foreach my $ep (@{$endpoints}) {
        my $conn = $conns->{$ep->cloud_connection_id};
        my $subnets = $syncer->get_peering_addresses_from_azure($conn, $ep->cloud_interconnect_id);
        warn Dumper($subnets);

        my $subnet_count = keys %$subnets;

        $ep->load_peers;

        # TODO Review peer sync logic
        # Ensure at least 1 peer for every subnet configured in Azure
        my $peers = $ep->peers;
        while (@$peers < $subnet_count) {
            my $peer = new OESS::Peer(
                db => $db,
                model => {
                    local_ip  => '192.168.200.249/30',
                    peer_asn  => 12076,
                    peer_ip   => '192.168.200.250/30',
                    status    => 'down'
                }
            );
            $peer->create(vrf_ep_id => $ep->vrf_endpoint_id);
            $ep->add_peer($peer);

            $peers = $ep->peers;
        }

        for (my $i = 0; $i < @$peers; $i++) {
            if ($i == 0) {
                $peers->[$i]->local_ip($subnets->{ipv4}->{local_ip});
                $peers->[$i]->peer_ip($subnets->{ipv4}->{remote_ip});
                $peers->[$i]->peer_asn($subnets->{ipv4}->{remote_asn});
                $peers->[$i]->ip_version($subnets->{ipv4}->{ip_version});
                $peers->[$i]->update;
            }
            elsif ($i == 1) {
                $peers->[$i]->local_ip($subnets->{ipv6}->{local_ip});
                $peers->[$i]->peer_ip($subnets->{ipv6}->{remote_ip});
                $peers->[$i]->peer_asn($subnets->{ipv4}->{remote_asn});
                $peers->[$i]->ip_version($subnets->{ipv6}->{ip_version});
                $peers->[$i]->update;
            }
            else {
                # Azure supports at most two peerings
            }
        }

        # foreach my $peer (@{$ep->peers}) {
            # if ($peer->ip_version eq 'ipv4') {
            #     $peer->peer_ip($subnets->{ipv4}->{remote_ip});
            #     $peer->local_ip($subnets->{ipv4}->{local_ip});
            # } else {
            #     $peer->peer_ip($subnets->{ipv6}->{remote_ip});
            #     $peer->local_ip($subnets->{ipv6}->{local_ip});
            # }
            # $peer->update;
        # }

        if ($ep->bandwidth != $conn->{properties}->{bandwidthInMbps}) {
            $ep->bandwidth($conn->{properties}->{bandwidthInMbps});
            $ep->update_db;
        }
    }
}

main();
