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


my $self;
my $client;
my $jsonObj = JSON->new->allow_nonref->convert_blessed->allow_blessed;


sub new {
    #my $class = shift;
    $self  = {
        config => '/etc/oess/database.xml',
        logger => Log::Log4perl->get_logger('OESS.Cloud.AWS'),
        @_
    };
    #bless $self, $class;
    my $creds = XML::Simple::XMLin($self->{config});
    $self->{creds} = $creds;
    warn "config " . Dumper $self->{creds};
warn "url " .  Dumper $creds->{'wsc'}->{'url'};
    $client = GRNOC::WebService::Client->new(
        url     => $self->{creds}->{'wsc'}->{'url'} . "/vrf.cgi",
        uid     => $self->{creds}->{'wsc'}->{'username'},
        passwd  => $self->{creds}->{'wsc'}->{'password'},
        verify_hostname => 0,
        #usePost => 1,
        debug   => 1
    ) or die "Cannot connect to webservice";
    #warn "client after creating " . Dumper $client;
}

new();

# Get VRFs from OESS db
my $workgroup_id = 3; # TODO: make this configurable

if ( defined $client ) {
my $res = $client->get_vrfs( workgroup_id => $workgroup_id );
warn "res: " . Dumper $res;
#my $data = $res->data();
    #warn "data " . Dumper $data;
} else {
    warn "client not defined";
}


$self->{connections} = {};

foreach my $conn (@{$self->{creds}->{cloud}->{connection}}) {
    $self->{connections}->{$conn->{interconnect_id}} = $conn;
}
#return $self;


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

get_vrf_aws_details( "dxcon-fgm77851", ,$resp );

sub get_vrf_aws_details {
    my ( $cloud_interconnect_id, $cloud_connection_id, $resp ) = @_;
    
    my $ret = grep { $_->ConnectionId eq $cloud_interconnect_id  } @{$resp->{'VirtualInterfaces'}};
    warn "RET \n" . Dumper $ret;

    die;

    return $ret;

}

my $virtual_interfaces = $resp->{'VirtualInterfaces'};
warn "interfaces \n";
#my $json = $resp->freeze();
#warn $json->encode( $virtual_interfaces );

warn "aws resp " . Dumper ( $resp );

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
        #'AuthKey',
        'VirtualGatewayId',

    );

    my $results = {};
    for my $field ( @fields ) {
        $results->{$field} = $intf->{$field};

    }
    warn "RESULTS\n" . Dumper $results;



}


