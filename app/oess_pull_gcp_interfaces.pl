#!/usr/bin/perl

# cron script for pulling down gcp virtual interface addresses

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Log::Log4perl;
use XML::Simple;
use GRNOC::WebService::Client;
use OESS::Config;
use OESS::Cloud::GCP;

my $logger;

sub main{
    my $logger = Log::Log4perl->get_logger('OESS.Cloud.GCP.Syncer');
    my $config = OESS::Config->new();
    my $client = connect_to_ws($config);

    my $workgroup_id = find_gcp_workgroup($client, $config);

    $client->set_url($config->base_url() . "/services/vrf.cgi");
    my $vrfs = $client->get_vrfs(workgroup_id => $workgroup_id);
    die $client->get_error if !defined $vrfs;

    my $gcp_ints = get_gcp_virtual_interface($config);

    compare_and_update_vrfs( vrfs => $vrfs, gcp_ints => $gcp_ints, client => $client);
}

sub find_gcp_workgroup{
    my $client = shift;
    my $config = shift;

    my $cloud_config = $config->get_cloud_config();

    my $wg_name;

    foreach my $cloud (@{$cloud_config->{'connection'}}){
        if($cloud->{'interconnect_type'} eq 'gcp-partner-interconnect'){
            $wg_name = $cloud->{'workgroup'};
        }
    }

    $client->set_url($config->base_url() . "/services/user.cgi");
    my $res = $client->get_current();
    die $client->get_error if !defined $res;

    my $workgroups = $res->{'results'}->[0]->{'workgroups'};
    foreach my $wg (@$workgroups){
        if($wg->{'name'} eq $wg_name){
            return $wg->{'workgroup_id'};
        }
    }
}



sub connect_to_ws {
    my $config = shift;

    my $creds = $config->get_cloud_config();

    my $client = GRNOC::WebService::Client->new(
        url     => $config->base_url() . "/services/vrf.cgi",
        uid     => $creds->{'user'},
        passwd  => $creds->{'password'},
        realm   => $creds->{'realm'},
        debug   => 0,
        timeout => 120,
        verify_hostname  => 0,
        ) or die "Cannot connect to webservice";

    return $client;
}


sub get_gcp_virtual_interface{
    my $config = shift;

    my @gcp_conns;

    my $gcp = OESS::Cloud::GCP->new();

    foreach my $cloud (@{$config->get_cloud_config()->{'connection'}}){
        if($cloud->{'interconnect_type'} eq 'gcp-partner-interconnect'){

            my $attachments = $gcp->get_aggregated_interconnect_attachments(
                interconnect_id => $cloud->{'interconnect_id'}
            );

            foreach my $region (keys %{$attachments->{items}}) {
                foreach my $attachment (@{$attachments->{items}->{$region}->{interconnectAttachments}}) {
                    push @gcp_conns, $attachment;
                }
            }

            last;
        }
    }

    return \@gcp_conns;
}

sub compare_and_update_vrfs{
    my %params = @_;
    my $vrfs = $params{'vrfs'};
    my $gcp_ints = $params{'gcp_ints'};
    my $client = $params{'client'};

    foreach my $vrf (@$vrfs) {
        foreach my $endpoint ( @{$vrf->{endpoints}} ) {
            next if ( !defined( $endpoint->{cloud_connection_id} ) );
            my $connection_id = $endpoint->{cloud_connection_id};   

            warn "get_vrf_gcp_details";
            my $peering = get_vrf_gcp_details(gcp_ints => $gcp_ints, cloud_connection_id => $connection_id);
            next if(!defined($peering) || $peering eq '');

            my $update = update_endpoint_values($endpoint->{'peers'}->[0], $peering);
            if ($endpoint->{mtu} != $peering->{mtu}) {
                $update = 1;
                $endpoint->{mtu} = $peering->{mtu}
            }
            if($update){
                update_oess_vrf($vrf,$client);
            }else{
                warn "NO Update required for VRF: " . $vrf->{'vrf_id'} . "\n";
            }
        }
    }
}

sub update_oess_vrf{
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
                             peer_asn => $p->{'peer_asn'},
                             md5_key => $p->{'md5_key'},
                             local_ip => $p->{'local_ip'},
                             vrf_ep_peer_id => $p->{'vrf_ep_peer_id'}});
        }
        push(@{$params{'endpoint'}},encode_json({ interface => $ep->{'interface'},
                                                  node => $ep->{'node'},
                                                  tag => $ep->{'tag'},
                                                  bandwidth => $ep->{'bandwidth'},
                                                  inner_tag => $ep->{'inner_tag'},
                                                  vrf_endpoint_id => $ep->{'vrf_endpoint_id'},
                                                  circuit_ep_id => $ep->{'circuit_ep_id'},
                                                  cloud_gateway_type => $ep->{'mtu'},
                                                  peers => \@peerings}));
    }

    my $res = $client->provision(%params);
}

sub get_vrf_gcp_details {
    my %params = @_;
    my $cloud_connection_id = $params{'cloud_connection_id'};
    my $virtual_interfaces = $params{'gcp_ints'};

    foreach my $gcp (@$virtual_interfaces){
        if ( $gcp->{name} ne $cloud_connection_id ) {
            next;
        }
        warn "Found\n";
        return $gcp
    }
}


sub update_endpoint_values {
    my ($vrf_peer, $gcp_peer) = @_;

    my $update = 0;

    if($vrf_peer->{peer_ip} ne $gcp_peer->{cloudRouterIpAddress}){
        $vrf_peer->{peer_ip} = $gcp_peer->{cloudRouterIpAddress};
        $update = 1;
    }
    if($vrf_peer->{peer_asn} ne 16550){
        $vrf_peer->{peer_asn} = 16550;
        $update = 1;
    }
    if(!defined($vrf_peer->{md5_key}) || $vrf_peer->{md5_key} ne ''){
        $vrf_peer->{md5_key} = '';
        $update = 1;
    }
    if($vrf_peer->{local_ip} ne $gcp_peer->{customerRouterIpAddress}){
        $vrf_peer->{local_ip} = $gcp_peer->{customerRouterIpAddress};
        return 1;
    }
    if($update){
        return 1;
    }else{
        return 0;
    }
}


main();
