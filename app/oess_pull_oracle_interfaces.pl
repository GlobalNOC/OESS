#!/usr/bin/perl

# cron script for syncing connections between oess and oracle cloud

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Log::Log4perl;
use XML::Simple;


use OESS::DB;
use OESS::Cloud::Oracle;
use OESS::Cloud::OracleSyncer;
use OESS::Config;


Log::Log4perl::init_and_watch('/etc/oess/logging.conf',10);
my $logger = Log::Log4perl->get_logger('OESS.Cloud.OracleSyncer');


sub main {
    my $config_path = "/etc/oess/database.xml";
    my $db = new OESS::DB(config => $config_path);

    my $syncer = new OESS::Cloud::OracleSyncer(
        config => new OESS::Config(config_filename => $config_path),
        oracle => new OESS::Cloud::Oracle(config => $config_path)
    );

    my ($conns, $oracle_err) = $syncer->fetch_virtual_circuits_from_oracle();
    die $oracle_err if defined $oracle_err;

    my ($endpoints, $err) = $syncer->fetch_oracle_endpoints_from_oess();
    die $err if defined $err;

    # endpoint_index using Oracle terminology:
    # -> virtualCircuitId -> crossConnectOrCrossConnectGroupId
    #
    # endpoint_index using OESS terminology
    # -> cloud_account_id -> cloud_interconnect_id
    my $endpoint_index = {};
    foreach my $ep (@{$endpoints}) {
        if (!defined $endpoint_index->{$ep->cloud_account_id}) {
            $endpoint_index->{$ep->cloud_account_id} = {};
        }
        $endpoint_index->{$ep->cloud_account_id}->{$ep->cloud_interconnect_id} = $ep;
    }

    foreach my $ocid (keys %$conns) {
        if ($conns->{$ocid}->{bgpManagement} eq 'PROVIDER_MANAGED') {
            my $err = $syncer->update_remote_peers(id => $ocid, endpoints => $endpoint_index->{$ep->cloud_account_id});
            $logger->error($err) if defined $err;
        }
        elsif ($conns->{$ocid}->{bgpManagement} eq 'ORACLE_MANAGED') {
            foreach my $cc (@{$conns->{$ocid}->{crossConnectMappings}}) {
                my $cloud_interconnect_id = $cc->{crossConnectOrCrossConnectGroupId};
                my $ep = $endpoint_index->{$ocid}->{$cloud_interconnect_id};
                if (!defined $ep) {
                    $logger->warn("Unexpected CrossConnectMapping encountered on $cloud_interconnect_id for VirtualCircuit $ocid.");
                    next;
                }
                my $remote_peers = $syncer->get_peering_addresses_from_oracle($conns->{$ocid}, $cloud_interconnect_id);

                my $err = $syncer->update_local_peers(
                    endpoint     => $ep
                    remote_peers => $remote_peers,
                );
                $logger->error($err) if defined $err;
                delete $endpoint_index->{$ocid}->{$cloud_interconnect_id};
            }
        }
    }

    foreach my $ocid (keys %{$endpoint_index}) {
        foreach my $cloud_interconnect_id (keys %{$endpoint_index->{$ocid}}) {
            my $ep = $endpoint_index->{$ocid}->{$cloud_interconnect_id};
            my $id = (defined $ep->vrf_id) ? $ep->vrf_id : $ep->circuit_id;
            $ep->decom;

            delete $endpoint_index->{$ocid}->{$cloud_interconnect_id};
            $logger->warn("Details for VirtualCircuit $ocid on $cloud_interconnect_id not reported by Oracle. Removed endpoint from Connection $id.");
        }
    }
}

main();
