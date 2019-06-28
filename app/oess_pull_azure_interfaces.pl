#!/usr/bin/perl

# cron script for syncing cloud connection bandwidth

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Log::Log4perl;
use XML::Simple;
use GRNOC::WebService::Client;
use OESS::Config;
use OESS::Cloud::Azure;
use OESS::Endpoint;

my $logger;

sub main{
    my $logger = Log::Log4perl->get_logger('OESS.Cloud.Azure.Syncer');
    my $config = OESS::Config->new();
    my $client = connect_to_ws($config);

    my @azure_cloud_accounts_config = fetch_azure_cloud_account_configs($client, $config);
    foreach my $cloud (@azure_cloud_accounts_config) {
        my $workgroup_name = $cloud->{workgroup};
        my $workgroup_id = fetch_workgroup_id_from_name($client, $config, $workgroup_name);
        if(!defined($workgroup_id)) {
            warn "Could not find workgroup id for workgroup $workgroup_name";
            next;
        }
        $client->set_url($config->base_url() . "/services/vrf.cgi");
        my $vrfs = $client->get_vrfs(workgroup_id => $workgroup_id);
        if (!($cloud->{interconnect_type} eq 'azure-express-route')) {
            next;
        }
        my $azure = OESS::Cloud::Azure->new();
        my $azure_connections = ($azure->expressRouteCrossConnections($cloud->{interconnect_id}));
        reconcile_oess_vrfs($config, $vrfs, $azure_connections, $client);
    }
}

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

sub update_oess_vrf {
    my $vrf = shift;
    my $client = shift;
    my %params;
    $params{'skip_cloud_provisioning'} = 1;
    $params{'vrf_id'} = $vrf->{'vrf_id'};
    $params{'name'} = $vrf->{'name'};
    $params{'workgroup_id'} = $vrf->{'workgroup'}->{'workgroup_id'};
    $params{'description'} = $vrf->{'description'};
    $params{'prefix_limit'} = $vrf->{'prefix_limit'};
    $params{'local_asn'} = $vrf->{'local_asn'};

    $params{'endpoint'} = ();
    foreach my $ep (@{$vrf->{'endpoints'}}){
        my @peerings;
        foreach my $p (@{$ep->{'peers'}}){
            push(@peerings,{ peer_ip => $p->{'peer_ip'},
                             asn => $p->{'peer_asn'},
                             key => $p->{'md5_key'},
                             local_ip => $p->{'local_ip'}});
        }
        push(@{$params{'endpoint'}},encode_json({ interface => $ep->{'interface'}->{'name'}, 
                                                  node => $ep->{'node'}->{'name'},
                                                  tag => $ep->{'tag'},
                                                  bandwidth => $ep->{'bandwidth'},
                                                  inner_tag => $ep->{'inner_tag'},
                                                  peerings => \@peerings}));
    
        
    }
    
    my $res = $client->provision(%params);
    warn Dumper($res);
}

sub reconcile_oess_vrfs {
    my $config = shift;
    my $vrfs = shift;
    my $azure_connections = shift;
    my $client = shift;

    foreach my $vrf (@$vrfs) {
        my $update_needed = 0;
        foreach my $endpoint (@{$vrf->{endpoints}}) {
            my $connection_id = $endpoint->{interface}->{cloud_interconnect_id};  
            next if ( !defined( $connection_id ) );
            my $azure_connection = get_connection_by_id($azure_connections, $connection_id);
            next if(!defined($azure_connection));

            # For now, just ensure the bandwidth is synced:
            my $cloud_bandwidth = $azure_connection->{properties}->{bandwidthInMbps};
            if (!$cloud_bandwidth || $endpoint->{bandwidth} eq $cloud_bandwidth) {
                next;
            }
            $endpoint->{bandwidth} = $cloud_bandwidth;
            $update_needed = 1;
        }

        if ($update_needed) {
            update_oess_vrf($vrf, $client);  
        }  
    }
}

sub fetch_workgroup_id_from_name {
    my $client = shift;
    my $config = shift;
    my $workgroup_name = shift;
    $client->set_url( $config->base_url() . "/services/data.cgi");
    my $res = $client->get_workgroups();
    my $workgroups = $res->{'results'};
    foreach my $wg (@$workgroups){
        if($wg->{'name'} eq $workgroup_name){
            return $wg->{'workgroup_id'};
        }
    }
    return undef;
}

sub fetch_azure_cloud_account_configs{
    my $client = shift;
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

sub connect_to_ws {
    my $config = shift;

    my $creds = $config->get_cloud_config();
    my $client = GRNOC::WebService::Client->new(
        url     => $config->base_url() . "services/vrf.cgi",
        uid     => $creds->{'user'},
        passwd  => $creds->{'password'},
        realm   => $creds->{'realm'},
        debug   => 0,
        timeout => 120
        ) or die "Cannot connect to webservice";

    return $client;
}

main();
