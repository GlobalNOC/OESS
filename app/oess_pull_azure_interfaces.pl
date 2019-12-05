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

my $logger;

sub main{
    my $logger = Log::Log4perl->get_logger('OESS.Cloud.Azure.Syncer');
    my $config = OESS::Config->new();
    my $db = OESS::DB->new();

    my @azure_cloud_accounts_config = fetch_azure_cloud_account_configs($config);
    my $azure = OESS::Cloud::Azure->new();

    my ($endpoints, $error) = OESS::DB::Endpoint::fetch_all(
        db => $db,
        cloud_interconnect_type => 'azure-express-route'
    );

    foreach my $cloud (@azure_cloud_accounts_config) {
        my $azure_connections = ($azure->expressRouteCrossConnections($cloud->{interconnect_id}));
        reconcile_oess_endpoints($db, $endpoints, $azure_connections);
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

    foreach my $endpoint (@$endpoints) {
        my $azure_connection = get_connection_by_id(
            $azure_connections,
            $endpoint->{cloud_connection_id}
        );
        next if (!defined $azure_connection);

        my $cloud_bandwidth = $azure_connection->{properties}->{bandwidthInMbps};
        if (!$cloud_bandwidth || $endpoint->{bandwidth} eq $cloud_bandwidth) {
            next;
        }

        my $ep = new OESS::Endpoint(db => $db, model => $endpoint);
        $ep->bandwidth($cloud_bandwidth);

        my $error = $ep->update_db;
        if (defined $error) {
            warn $error;
        }
    }
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
