#!/usr/bin/perl

# cron script for pulling down aws virtual interface addresses

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Log::Log4perl;
use Paws;
use XML::Simple;
#use MooseX::Storage;
#    with Storage('format' => 'JSON');
    #with Storage('format' => 'JSON', 'io' => 'File');


my $self;

my $jsonObj = JSON->new->allow_nonref->convert_blessed->allow_blessed;


sub new {
    #my $class = shift;
    $self  = {
        config => '/etc/oess/database.xml',
        logger => Log::Log4perl->get_logger('OESS.Cloud.AWS'),
        @_
    };
    #bless $self, $class;

    $self->{creds} = XML::Simple::XMLin($self->{config});
    $self->{connections} = {};

    foreach my $conn (@{$self->{creds}->{cloud}->{connection}}) {
        $self->{connections}->{$conn->{interconnect_id}} = $conn;
    }
    #return $self;
}

new();

#warn "self-connections " . Dumper $self->{connections};
#warn "self-creds " . Dumper $self->{creds};

# old
# region => $self->{connections}->{$interconnect_id}->{region}

  my $dc = Paws->service(
        'DirectConnect',
        region => "us-east-1"
    );

# DescribeVirtualInterfaces

    my $resp = $dc->DescribeVirtualInterfaces();

    my $virtual_interfaces = $resp->{'VirtualInterfaces'};
    warn "interfaces \n";
    #my $json = $resp->freeze();
    #warn $json->encode( $virtual_interfaces );

    warn "json " . Dumper ( $resp );

    for my $intf ( @$virtual_interfaces ) {
        my $bgp_peers = $intf->BgpPeers;
        #warn "bgp peers " . Dumper @{ $interface->BgpPeers }[0]->AddressFamily;

        my @fields = (
            'Vlan', 
            'VirtualInterfaceState', 
            'ConnectionId',
            'AmazonAddress',
            'Asn',
            'OwnerAccount',
            'CustomerAddress',
            'Location',
            'AmazonSideAsn',
            'DirectConnectGatewayId',
            'VirtualInterfaceType',
            'VirtualInterfaceName',
            'VirtualInterfaceId',
            'AddressFamily',
            'AuthKey',
            'VirtualGatewayId',

        );

        my $results = {
            #vlan => $intf->Vlan,
            #state => $intf->VirtualInterfaceState,
            #connection_id => $intf->ConnectionId,
            #amazon_address => $intf->AmazonAddress


            

        };
        for my $field ( @fields ) {
            $results->{$field} = $intf->{$field};

        }
        warn "RESULTS\n" . Dumper $results;



    }


