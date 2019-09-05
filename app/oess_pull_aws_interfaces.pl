#!/usr/bin/perl

# cron script for pulling down aws virtual interface addresses

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Log::Log4perl;
use Paws;
use XML::Simple;
use GRNOC::WebService::Client;
use OESS::Config;

my $logger;

sub main{
    my $logger = Log::Log4perl->get_logger('OESS.Cloud.AWS.Syncer');
    my $config = OESS::Config->new();
    my $client = connect_to_ws($config);

    my $workgroup_id = find_aws_workgroup($client, $config);

    $client->set_url($config->base_url() . "/services/vrf.cgi");
    my $vrfs = $client->get_vrfs( workgroup_id => $workgroup_id);

    my $aws_ints = get_aws_virtual_interface($config);

    compare_and_update_vrfs( vrfs => $vrfs, aws_ints => $aws_ints, client => $client);
}

sub find_aws_workgroup{
    my $client = shift;
    my $config = shift;

    my $cloud_config = $config->get_cloud_config();

    my $wg_name;

    foreach my $cloud (@{$cloud_config->{'connection'}}){
        if($cloud->{'interconnect_type'} eq 'aws-hosted-vinterface' || $cloud->{'interconnect_type'} eq 'aws-hosted-connection'){
            $wg_name = $cloud->{'workgroup'};
        }
    }

    $client->set_url( $config->base_url() . "/services/user.cgi");
    my $res = $client->get_current();

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
        url     => $config->base_url() . "services/vrf.cgi",
        uid     => $creds->{'user'},
        passwd  => $creds->{'password'},
        realm   => $creds->{'realm'},
        debug   => 0,
        timeout => 120
        ) or die "Cannot connect to webservice";

    return $client;
}


sub get_aws_virtual_interface{
    my $config = shift;
    
    my @aws_conns;

    foreach my $cloud (@{$config->get_cloud_config()->{'connection'}}){
        if($cloud->{'interconnect_type'} eq 'aws-hosted-vinterface' || $cloud->{'interconnect_type'} eq 'aws-hosted-connection'){
            $ENV{'AWS_ACCESS_KEY'} = $cloud->{access_key};
            $ENV{'AWS_SECRET_KEY'} = $cloud->{secret_key};
            
            my $dc = Paws->service(
                'DirectConnect',
                region => "us-east-1"
                );
            
            
            # DescribeVirtualInterfaces    
            my $aws_res = $dc->DescribeVirtualInterfaces();
            warn Dumper($aws_res->{VirtualInterfaces});
            push(@aws_conns, @{$aws_res->{VirtualInterfaces}});
        }

    }        

    return \@aws_conns;
}

sub compare_and_update_vrfs{
    my %params = @_;
    my $vrfs = $params{'vrfs'};
    my $aws_ints = $params{'aws_ints'};
    my $client = $params{'client'};

    foreach my $vrf (@$vrfs) {
        foreach my $endpoint ( @{$vrf->{endpoints}} ) {
            next if ( !defined( $endpoint->{cloud_connection_id} ) );
            my $connection_id = $endpoint->{cloud_connection_id};   
            my $aws_peering = get_vrf_aws_details( aws_ints => $aws_ints, cloud_connection_id => $connection_id );
	    next if (!defined($aws_peering));
            my $update = update_endpoint_values( $endpoint->{'peers'}->[0], $aws_peering );
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
                                                  peers => \@peerings}));
    }

    # warn Dumper(\%params);

    my $res = $client->provision(%params);
    warn Dumper($res);
}

sub get_vrf_aws_details {
    my %params = @_;
    my $cloud_connection_id = $params{'cloud_connection_id'};
    my $virtual_interfaces = $params{'aws_ints'};

    warn Dumper(@$virtual_interfaces);

    foreach my $aws (@$virtual_interfaces){
        warn "AWS VirtualInterfaceId: " . $aws->VirtualInterfaceId . " vs " . $cloud_connection_id . "\n";
        if ( $aws->VirtualInterfaceId ne $cloud_connection_id ) {
            warn "Not it\n";
            next;
        }
        warn "Found\n";
        return $aws
    }
}


sub update_endpoint_values {
    my ( $vrf_peer, $aws_peer ) = @_;

    my $update = 0;

    if($vrf_peer->{peer_ip} ne $aws_peer->AmazonAddress){
        $vrf_peer->{peer_ip} = $aws_peer->AmazonAddress;
        $update = 1;
    }
    if($vrf_peer->{peer_asn} ne $aws_peer->AmazonSideAsn){
        $vrf_peer->{peer_asn} = $aws_peer->AmazonSideAsn;
        $update = 1;
    }
    if(!defined($vrf_peer->{md5_key}) || $vrf_peer->{md5_key} ne $aws_peer->AuthKey){
        $vrf_peer->{md5_key} = $aws_peer->AuthKey;
        $update = 1;
    }
    if($vrf_peer->{local_ip} ne $aws_peer->CustomerAddress){
        $vrf_peer->{local_ip} = $aws_peer->CustomerAddress;
        return 1;
    }
    if($update){
        return 1;
    }else{
        return 0;
    }
}


main();
