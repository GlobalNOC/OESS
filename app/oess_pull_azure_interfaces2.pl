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
        my $remote_peers = $syncer->get_peering_addresses_from_azure($conn, $ep->cloud_interconnect_id);

        $ep->load_peers;
        my $local_peers = $ep->peers;

        my $i = 0;
        while ($i < @$remote_peers) {
            my $peer;
            if ($i+1 > @$local_peers) {
                # While more remote_peers than local_peers create one
                my $peer = new OESS::Peer(
                    db => $db,
                    model => {
                        local_ip   => $remote_peers->[$i]->{local_ip},
                        peer_asn   => $remote_peers->[$i]->{remote_asn},
                        peer_ip    => $remote_peers->[$i]->{remote_ip},
                        status     => 'up',
                        ip_version => $remote_peers->[$i]->{ip_version}
                    }
                );
                $peer->create(vrf_ep_id => $ep->vrf_endpoint_id);
            } else {
                $local_peers->[$i]->local_ip($remote_peers->[$i]->{local_ip});
                $local_peers->[$i]->peer_asn($remote_peers->[$i]->{remote_asn});
                $local_peers->[$i]->peer_ip($remote_peers->[$i]->{remote_ip});
                $local_peers->[$i]->ip_version($remote_peers->[$i]->{ip_version});
                $local_peers->[$i]->update;
            }

            $i++;
        }

        while ($i < @$local_peers) {
            # While more local_peers than remote_peers remove one
            $local_peers->[$i]->decom;
            $i++;
        }

        if ($ep->bandwidth != $conn->{properties}->{bandwidthInMbps}) {
            $ep->bandwidth($conn->{properties}->{bandwidthInMbps});
            $ep->update_db;
        }
    }
}

main();
