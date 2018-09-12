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

#use MooseX::Storage;
#    with Storage('format' => 'JSON');
    #with Storage('format' => 'JSON', 'io' => 'File');


my $client;
my $config;
my $logger;
my $creds;
my $connections = {};
my $jsonObj = JSON->new->allow_nonref->convert_blessed->allow_blessed;

sub new {
    $config = '/etc/oess/database.xml';
    $logger = Log::Log4perl->get_logger('OESS.Cloud.AWS');
    #bless $self, $class;
    $creds = XML::Simple::XMLin($config);
    $client = GRNOC::WebService::Client->new(
        url     => $creds->{wsc}->{url} . "/vrf.cgi",
        uid     => $creds->{wsc}->{username},
        passwd  => $creds->{wsc}->{password},
        verify_hostname => 0,
        #usePost => 1,
        debug   => 0
    ) or die "Cannot connect to webservice";
    #warn "client after creating " . Dumper $client;
}

new();

# Get VRFs from OESS db
my $workgroup_id = 3; # TODO: make this configurable

my $oess_res;
if ( defined $client ) {
    $oess_res = $client->get_vrfs( workgroup_id => $workgroup_id );
    warn "oess_res: " . Dumper $oess_res;
    if ( ! defined $oess_res ) {
        die "Error retrieving VRFs from webservice " . $client->get_error();

    }
#my $data = $oess_res->data();
    #warn "data " . Dumper $data;
} else {
    warn "client not defined";
}

my %aws_matches = ();

foreach my $conn (@{$creds->{cloud}->{connection}}) {
    $connections->{$conn->{interconnect_id}} = $conn;
}

my $dc = Paws->service(
    'DirectConnect',
    region => "us-east-1"
);

# DescribeVirtualInterfaces

my $aws_res = $dc->DescribeVirtualInterfaces();

my $vrf_id_filter = 609;

my $oess_updates = [];
foreach my $vrf (@$oess_res) {
    #warn "vrf " . Dumper $vrf;
    foreach my $endpoint ( @{$vrf->{endpoints}} ) {
        next if ( not defined( $endpoint->{cloud_connection_id} ) );
        next if ( defined ( $vrf_id_filter ) && $vrf_id_filter != $endpoint->{tag} );
        #warn "endpoint " . Dumper $endpoint;
        #my $interconnect_id = $endpoint->{interface}->{cloud_interconnect_id};
        my $connection_id = $endpoint->{cloud_connection_id};
        my $vlan_id = $endpoint->{tag};
        #my $vlan_id = $endpoint->{cloud_connection_id};
        warn "VLAN_ID " . Dumper $vlan_id;
        warn "NUMBER OF PEERS " . @{$endpoint->{peers}};
        my $aws_vrfs = get_vrf_aws_details( $connection_id, $vlan_id );
        update_endpoint_values( $endpoint, $aws_vrfs );
        push @$oess_updates, $vrf;
    }
}

warn "OESS_UPDATES " . Dumper $oess_updates;

my $update_requests = reformat( $oess_updates );

foreach my $ur ( @$update_requests ) {


}

sub reformat {
    my ( $updates ) = @_;

    my $updates_out = [];

    my @top_level_fields = ( 'local_asn', 'prefix_limit', 'name', 'vrf_id', 'description' );


    foreach my $row (@$updates) {
        my $update = {};
        $update->{workgroup_id} = $workgroup_id;
        #$update->{endpoint} = $jsonObj->encode( $row->{endpoints} );
        my $endpoints_for_update = [];
        foreach my $endpoint (@{$row->{endpoints}}) {
            my $ep = {};
            $ep->{interface}->{node}->{name} = $endpoint->{node}->{name};
            $ep->{interface}->{name} = $endpoint->{interface}->{name};
            $ep->{tag} = $endpoint->{tag};
            $ep->{inner_tag} = $endpoint->{inner_tag};
            $ep->{cloud_account_id} = $endpoint->{cloud_account_id};
            $ep->{cloud_connection_id} = $endpoint->{cloud_connection_id};
            $ep->{peerings} = $endpoint->{peers};

            #$ep = $jsonObj->encode( $ep );

            push @$endpoints_for_update, $ep;

        }
        $update->{endpoint} = $jsonObj->encode( $endpoints_for_update );

        foreach my $field( @top_level_fields ) {
            $update->{ $field } = $row->{ $field };
        }
        warn "UPDATE " . Dumper $update;
        push @$updates_out, $update;

    }


    return $updates_out;



}

sub update_endpoint_values {
    my ( $endpoint, $aws_vrfs ) = @_;
    return if ( not (defined $aws_vrfs) || @$aws_vrfs == 0);

    foreach my $aws (@$aws_vrfs ) {
        warn "updating aws " . $aws->VirtualInterfaceId;
        #warn "aws values " . Dumper $aws;
        $endpoint->{interface}->{cloud_interconnect_id} = $aws->ConnectionId if  $aws->ConnectionId;
        $endpoint->{cloud_account_id} = $aws->OwnerAccount if $aws->OwnerAccount;
        # TODO: handle more than one set of peers. currently we assume one
        my $peer = $endpoint->{peers}->[0];
        warn "PEER " . Dumper $peer;
        $peer->{peer_ip} = $aws->AmazonAddress if $aws->AmazonAddress;
        $peer->{peer_asn} = $aws->AmazonSideAsn if $aws->AmazonSideAsn;
        $peer->{md5_key} = $aws->AuthKey if $aws->AuthKey;
        $peer->{local_ip} = $aws->CustomerAddress if $aws->CustomerAddress;
        warn "PEER AFTER CHANGES " . Dumper $peer;
        $endpoint->{peers}->[0] = $peer;


    }

    warn "ENDPOINT AFTER UPDATES vlan " . $endpoint->{tag} . "!!\n"  . Dumper $endpoint;
}

# Updates a value, but only if the new value is defined
# Assumes that $old is a scalar, but ...
# if $key is provided then $old->{ $key } is used for the old value

sub _update_value {
    my ( $old, $new, $key ) = @_;
    # by default, return the "old" (existing) value
    my $ret = $old;

    if ( defined $new ) {
        if ( $key ) {
            my $oldval = $old->{ $key };
        }
        $ret = $new;
    }
    return $ret;
}

warn "aws_matches " . Dumper \%aws_matches;


sub get_vrf_aws_details {
    my ( $cloud_connection_id, $vlan_id ) = @_;

    #warn "aws_res: $aws_res";
    
    #my @ret = grep { $_->ConnectionId eq $cloud_interconnect_id } @{$aws_res->{VirtualInterfaces}};
    #warn "RET \n" . Dumper @ret;
    
    my @aws_details = (); 

    foreach my $aws (@{$aws_res->{VirtualInterfaces}}) {

        if ( $aws->VirtualInterfaceId ne $cloud_connection_id ) {
            next;
        }
        # key off cloud_connection_id
        warn "INTF ConnectionId matches $cloud_connection_id on vlan " . $vlan_id;
        my $key = $cloud_connection_id . "_" . $vlan_id;
        $aws_matches{$key} = 0 if ( not defined ( $aws_matches{ $key } ) );
        $aws_matches{$key}++;
        push @aws_details, $aws;
    }


    warn "AWS_DETAILS " . @aws_details;
    #warn "AWS_DETAILS " . Dumper @aws_details;

    return \@aws_details;

}
