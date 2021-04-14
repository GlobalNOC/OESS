#!/usr/bin/perl

# cron script for syncing cloud connection bandwidth

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Log::Log4perl;
use XML::Simple;

use OESS::Cloud::Azure;
use OESS::Config;
use OESS::DB;
use OESS::DB::Endpoint;
use OESS::Endpoint;

Log::Log4perl::init_and_watch('/etc/oess/logging.conf',10);

my $logger = Log::Log4perl->get_logger('OESS.Cloud.Azure.Syncer');;

sub main{
    my $config = OESS::Config->new();
    my $db = OESS::DB->new();

    my @azure_cloud_accounts_config = fetch_azure_cloud_account_configs($config);
    my $azure = OESS::Cloud::Azure->new();

    my ($endpoints, $error) = OESS::DB::Endpoint::fetch_all(
        db => $db,
        cloud_interconnect_type => 'azure-express-route'
    );

    
    foreach my $cloud (@azure_cloud_accounts_config) {
        my $connectionsWithNoPeering = ($azure->expressRouteCrossConnections($cloud->{interconnect_id}));
        my $azure_connections = [];
        foreach my $conn (@$connectionsWithNoPeering) {
            my $connWithPeering = $azure->expressRouteCrossConnection($cloud->{interconnect_id}, $conn->{name});
            push($azure_connections, $connWithPeering);
        }
        reconcile_oess_endpoints($db, $endpoints, $azure_connections, $cloud->{interconnect_id});
    }

}

=head2 get_connection_by_id

get_connection_by_id gets the Azure CrossConnection associated to an
OESS Endpoint's C<cloud_connection_id>.

=cut
sub get_connection_by_id {
    my $connections = shift;
    my $id = shift;
    foreach my $connection (@$connections) {
        if ($connection->{id} eq $id) {
            return $connection;
        }
    }
    return undef;
}


=head2 reconcile_oess_endpoints

reconcile_oess_endpoints looks up the bandwidth as defined via the
Azure ExpressRoute portal and ensures that OESS has the same value.

=cut
sub reconcile_oess_endpoints {
    my $db = shift;
    my $endpoints = shift;
    my $azure_connections = shift;
    my $cloud_interconnect_id = shift;

    foreach my $endpoint (@$endpoints) {
        my $azure_connection = get_connection_by_id(
            $azure_connections,
            $endpoint->{cloud_connection_id}
        );
        next if (!defined $azure_connection);

        my $ep = new OESS::Endpoint(db => $db, model => $endpoint);
        $ep->load_peers();
        next if(! $cloud_interconnect_id eq $ep->cloud_interconnect_id());

        my $could_account_id = $azure_connection->{name};
        my $azure_subnet = find_matching_azure_subnet($azure_connection, $cloud_interconnect_id);
        my $endpoint_peer = get_endpoint_peer($ep, $cloud_interconnect_id, $could_account_id);

        next if(!defined $azure_subnet || !defined $endpoint_peer);

        if(increment_ip($endpoint_peer->{local_ip}, -1) ne $azure_subnet){
            $logger->info("MISMATCH: on could_account_id: $could_account_id cloud_interconnect_id: $cloud_interconnect_id azure_subnet: $azure_subnet but OESS is peering on $endpoint_peer->{local_ip}");
            update_endpoint_peer_ips($db, $azure_subnet, $endpoint_peer);
        }

        my $cloud_bandwidth = $azure_connection->{properties}->{bandwidthInMbps};
        if (!$cloud_bandwidth || $endpoint->{bandwidth} eq $cloud_bandwidth) {
            next;
        }

        $ep->bandwidth($cloud_bandwidth);

        my $error = $ep->update_db;
        if (defined $error) {
            warn $error;
        }
    }
}

sub find_matching_azure_subnet{
    my $azure_connection_info = shift;
    my $cloud_interconnect_id = shift;
    my $azure_peering_subnet;
    my $peering = $azure_connection_info->{properties}->{peerings};
    foreach my $ip (@$peering){
        if($cloud_interconnect_id =~ m/-SEC-/){
            $azure_peering_subnet = $ip->{properties}->{secondaryPeerAddresssubnet};
        }elsif($cloud_interconnect_id =~ m/-PRI-/){
            $azure_peering_subnet = $ip->{properties}->{primaryPeerAddresssubnet};
        }else{
            $azure_peering_subnet = undef;
        }
    }
    return $azure_peering_subnet;
}

sub get_endpoint_peer{
    my $endpoint = shift;
    my $cloud_interconnect_id = shift;
    my $cloud_account_id = shift;
    my $peers = $endpoint->peers();
    my $endpoint_ips =[];
    if($endpoint->cloud_interconnect_id() eq $cloud_interconnect_id && $endpoint->cloud_account_id() eq $cloud_account_id){
        foreach my $peer (@$peers){
            my $cloud_connetions = $peer->{db}->{configuration}->{cloud}->{connection};
            foreach my $conn (@$cloud_connetions){
                if( $conn->{interconnect_id} eq $cloud_interconnect_id){
                    return $peer;
                } 
            }
        }
    }
    return undef;
}

sub update_endpoint_peer_ips{
    my $db = shift;
    my $azure_subnet = shift;
    my $peer = shift;
    my $new_oess_ip = increment_ip($azure_subnet, 1);
    my $new_azure_ip = increment_ip($azure_subnet, 2);
    $logger->info("UPDATEING AZURE PEERING: changing $peer->{local_ip} to $new_oess_ip, and changing $peer->{peer_ip} to $new_azure_ip");
    $peer->{local_ip} = $new_oess_ip;
    $peer->{peer_ip} = $new_azure_ip;
    $peer->update;
}

sub increment_ip{
    my $ip = shift;
    my $increment = shift;
    $ip =~ m/^(\d\d?\d?)\.(\d\d?\d?)\.(\d\d?\d?)\.(\d\d?\d?)/;
    my $firstOctet = $1;
    my $secondOctet = $2;
    my $thirdOctet = $3;
    my $lastOctet = $4;
    $ip =~ m/\/(\d\d?)$/;
    my $subnet = $1;
    $lastOctet = int($lastOctet) + $increment;
    return "$firstOctet.$secondOctet.$thirdOctet.$lastOctet/$subnet";
}

sub fetch_azure_cloud_account_configs{
    my $config = shift;
    my @results = ();

    # Do this dance to ensure cloud_config is an array 
    # such that we can just iterate over it to gather accounts
    my $cloud_config = $config->get_cloud_config();
    if (!(ref($cloud_config->{connection}) eq 'ARRAY')) {
        $cloud_config->{connection} = [$cloud_config->{connection}];
    }

    foreach my $cloud (@{$cloud_config->{'connection'}}){
        if($cloud->{'interconnect_type'} eq 'azure-express-route'){
            push(@results, $cloud);
        }
    }
    return @results;
}

main();
