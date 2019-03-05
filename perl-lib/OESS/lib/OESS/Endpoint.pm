#!/usr/bin/perl

use strict;
use warnings;

package OESS::Endpoint;

use Digest::MD5 qw(md5_hex);

use OESS::DB;
use OESS::Interface;
use OESS::Entity;
use OESS::Node;
use OESS::Peer;
use OESS::Entity;
use Data::Dumper;


=head1 OESS::Endpoint

An C<Endpoint> represents an edge connection of a circuit or vrf.

=cut

=head2 new

B<Example 1:>

    my $json = {
        inner_tag           => undef,      # Inner VLAN tag (qnq only)
        tag                 => 1234,       # Outer VLAN tag
        cloud_account_id    => '',         # AWS account or GCP pairing key
        cloud_connection_id => '',         # Probably shouldn't exist as an arg
        entity              => 'us-east1', # Interfaces to select from
        bandwidth           => 100,        # Acts as an interface selector and validator
        workgroup_id        => 10,         # Acts as an interface selector and validator
        peerings            => [ {...} ]
    };
    my $endpoint = OESS::Endpoint->new(db => $db, type => 'vrf', model => $json);

B<Example 2:>

    my $json = {
        inner_tag           => undef,      # Inner VLAN tag (qnq only)
        tag                 => 1234,       # Outer VLAN tag
        cloud_account_id    => '',         # AWS account or GCP pairing key
        cloud_connection_id => '',         # Probably shouldn't exist as an arg
        node                => 'switch.1', # Name of node to select
        interface           => 'xe-7/0/1', # Name of interface to select
        bandwidth           => 100,        # Acts as an interface validator
        workgroup_id        => 10,         # Acts as an interface validator
        peerings            => [ {...} ]
    };
    my $endpoint = OESS::Endpoint->new(db => $db, type => 'vrf', model => $json);

=cut
sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.Endpoint");

    my %args = (
        details => undef,
        vrf_id => undef,
        db => undef,
        @_
    );

    my $self = \%args;
    
    bless $self, $class;

    $self->{'logger'} = $logger;

    if(!defined($self->{'db'})){
        $self->{'logger'}->error("No Database Object specified");
        return;
    }

    if(!defined($self->{'vrf_endpoint_id'}) || $self->{'vrf_endpoint_id'} == -1){
        
        $self->_build_from_model();

    }else{

        $self->_fetch_from_db();

    }

    return $self;
}

=head2 _build_from_model

=cut
sub _build_from_model{
    my $self = shift;
    
    $self->{'inner_tag'} = $self->{'model'}->{'inner_tag'};
    $self->{'tag'} = $self->{'model'}->{'tag'};
    $self->{'bandwidth'} = $self->{'model'}->{'bandwidth'};
    $self->{cloud_account_id} = $self->{model}->{cloud_account_id};
    $self->{cloud_connection_id} = $self->{model}->{cloud_connection_id};

    if (defined $self->{'model'}->{'interface'}) {
        $self->{'interface'} = OESS::Interface->new(db => $self->{'db'}, name => $self->{'model'}->{'interface'}, node => $self->{'model'}->{'node'});
        $self->{'entity'} = OESS::Entity->new(db => $self->{'db'}, interface_id => $self->{'interface'}->{'interface_id'}, vlan => $self->{'tag'});
    } else {
        $self->{'entity'} = OESS::Entity->new(db => $self->{'db'}, name => $self->{'model'}->{'entity'});

        # There are a few ways to select an Entity's interface.

        # The default selection method is to find the first interface
        # that has supports C<bandwidth> and has C<tag> available.

        # As there is only one interface per AWS Entity there is no
        # special selection method.

        # Interface selection for a GCP Entity is based purely on the
        # user provided GCP pairing key.

        # Interface selection for an Azure Entity is somewhat
        # irrelevent. Each interface of the Azure port pair is
        # configured similarly with the only difference between the
        # two being the peer addresses assigned to each.

        my $err = undef;
        foreach my $intf (@{$self->{entity}->interfaces()}) {
            my $valid_bandwidth = $intf->is_bandwidth_valid(bandwidth => $self->{model}->{bandwidth});
            if (!$valid_bandwidth) {
                $err = "The choosen bandwidth for this Endpoint is invalid.";
            }

            my $valid_vlan = 0;
            if (defined $self->{model}->{workgroup_id}) {
                $valid_vlan = $intf->vlan_valid(
                    vlan         => $self->{model}->{tag},
                    workgroup_id => $self->{model}->{workgroup_id}
                );
                if (!$valid_vlan) {
                    $err = "The selected workgroup cannot use vlan $self->{model}->{tag} on $self->{model}->{entity}.";
                }
            } else {
                warn "Endpoint model is missing workgroup_id. Skipping vlan validation.";
                $valid_vlan = 1;
            }

            if ($intf->cloud_interconnect_type eq 'gcp-partner-interconnect') {
                my @part = split(/\//, $self->{cloud_account_id});
                my $key_zone = 'zone' . $part[2];

                @part = split(/-/, $intf->cloud_interconnect_id);
                my $conn_zone = $part[4];

                if ($conn_zone ne $key_zone) {
                    $err = "The provided pairing key couldn't be used.";
                    $valid_vlan = 0;
                }
            }

            if ($valid_vlan && $valid_bandwidth) {
                $self->{interface} = $intf;
                last;
            }
        }

        if (!defined $self->{interface}) {
            die $err;
        }
    }

    if($self->{'type'} eq 'vrf'){
        $self->{'peers'} = [];
        my $last_octet = 2;

        foreach my $peer (@{$self->{'model'}->{'peerings'}}){
            # Peerings are auto-generated for cloud connection
            # endpoints. The user has only the option to select the ip
            # version used for peering.

            if (defined $self->{cloud_account_id} && $self->{cloud_account_id} ne '') {
                my $rand = rand();

                $peer->{asn} = 64512;
                $peer->{key} = md5_hex($rand);
                if ($peer->{version} == 4) {
                    $peer->{local_ip} = '172.31.254.' . $last_octet . '/31';
                    $peer->{peer_ip}  = '172.31.254.' . ($last_octet + 1) . '/31';
                } else {
                    $peer->{local_ip} = 'fd28:221e:28fa:61d3::' . $last_octet . '/127';
                    $peer->{peer_ip}  = 'fd28:221e:28fa:61d3::' . ($last_octet + 1) . '/127';
                }

                # Assuming we use .2 and .3 the first time around. We
                # can use .4 and .5 on the next peering.
                $last_octet += 2;
            }

            push(@{$self->{'peers'}}, OESS::Peer->new(db => $self->{'db'}, model => $peer, vrf_ep_peer_id => -1));
        }
    }

    #unit will be selected at creation....
    $self->{'unit'} = undef;
}

=head2 to_hash

=cut
sub to_hash{
    my $self = shift;
    my $obj;

    $obj->{'interface'} = $self->interface()->to_hash();
    $obj->{'node'} = $self->interface()->node()->to_hash();
    $obj->{'inner_tag'} = $self->inner_tag();
    $obj->{'tag'} = $self->tag();
    $obj->{'bandwidth'} = $self->bandwidth();
    $obj->{cloud_account_id} = $self->cloud_account_id();
    $obj->{cloud_connection_id} = $self->cloud_connection_id();
    if(defined($self->entity())){
        $obj->{'entity'} = $self->entity->to_hash();
    }
    if($self->{'type'} eq 'vrf'){

        my @peers;
        foreach my $peer (@{$self->{'peers'}}){
            push(@peers, $peer->to_hash());
        }

        $obj->{'peers'} = \@peers;
        $obj->{'vrf_id'} = $self->vrf_id();
        $obj->{'vrf_endpoint_id'} = $self->vrf_endpoint_id();

    }else{
        $obj->{'circuit_id'} = $self->circuit_id();
        $obj->{'circuit_endpoint_id'} = $self->circuit_endpoint_id();
    }
    
    $obj->{'type'} = $self->{'type'};
    $obj->{'unit'} = $self->{'unit'};
    return $obj;

}

=head2 from_hash

=cut
sub from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{'bandwidth'} = $hash->{'bandwidth'};
    $self->{'interface'} = $hash->{'interface'};

    $self->{cloud_account_id} = $hash->{cloud_account_id};
    $self->{cloud_connection_id} = $hash->{cloud_connection_id};

    if($self->{'type'} eq 'vrf'){
        $self->{'peers'} = $hash->{'peers'};
        $self->{'vrf_id'} = $hash->{'vrf_id'};
    }else{
        $self->{'circuit_id'} = $hash->{'circuit_id'};
    }

    $self->{'inner_tag'} = $hash->{'inner_tag'};
    $self->{'tag'} = $hash->{'tag'};
    $self->{'bandwidth'} = $hash->{'bandwidth'};

    $self->{'unit'} = $hash->{'unit'};

    $self->{'entity'} = OESS::Entity->new( db => $self->{'db'}, interface_id => $self->{'interface'}->{'interface_id'}, vlan => $self->{'tag'});
}

=head2 _fetch_from_db

=cut
sub _fetch_from_db{
    my $self = shift;
    
    my $db = $self->{'db'};
    my $hash;

    if($self->{'type'} eq 'circuit'){

        $hash = OESS::DB::Circuit::fetch_circuit(db => $db, circuit_id => $self->{'circuit_id'});
        
    }else{
        
        $hash = OESS::DB::VRF::fetch_endpoint(db => $db, vrf_endpoint_id => $self->{'vrf_endpoint_id'});
    
    }

    $self->from_hash($hash);

}

=head2 cloud_account_id

=cut
sub cloud_account_id {
    my $self = shift;
    my $value = shift;
    if (defined $value) {
        $self->{cloud_account_id} = $value;
    }
    return $self->{cloud_account_id};
}

=head2 cloud_connection_id

=cut
sub cloud_connection_id {
    my $self = shift;
    my $value = shift;
    if (defined $value) {
        $self->{cloud_connection_id} = $value;
    }
    return $self->{cloud_connection_id};
}

=head2 interface

=cut
sub interface{
    my $self = shift;
    return $self->{'interface'};
}

=head2 node

=cut
sub node{
    my $self = shift;
    return $self->{'interface'}->node();
}

=head2 type

=cut
sub type{
    my $self = shift;
    $self->{'type'};
}

=head2 peers

=cut
sub peers{
    my $self = shift;
    my $peers = shift;

    if(defined($peers)){
        $self->{'peers'} = $peers;
    }

    if(!defined($self->{'peers'})){
        return [];
    }

    return $self->{'peers'};
}

=head2 inner_tag

=cut
sub inner_tag{
    my $self = shift;
    my $inner_tag = shift;

    if (defined $inner_tag) {
        $self->{'inner_tag'} = $inner_tag;
    }
    return $self->{'inner_tag'};
}

=head2 tag

=cut
sub tag{
    my $self = shift;
    my $tag = shift;

    if (defined $tag) {
        $self->{'tag'} = $tag;
    }
    return $self->{'tag'};
}

=head2 bandwidth

=cut
sub bandwidth{
    my $self = shift;
    return $self->{'bandwidth'};
}

=head2 vrf_endpoint_id

=cut
sub vrf_endpoint_id{
    my $self = shift;
    return $self->{'vrf_endpoint_id'};
}

=head2 vrf_id

=cut
sub vrf_id{
    my $self = shift;
    return $self->{'vrf_id'};
}

=head2 circuit_id

=cut
sub circuit_id{
    my $self = shift;
    return $self->{'circuit_id'};
}

=head2 circuit_endpoint_id

=cut
sub circuit_endpoint_id{
    my $self = shift;
    return $self->{'circuit_endpoint_id'};
}

=head2 entity

=cut
sub entity{
    my $self = shift;
    return $self->{'entity'};
}

=head2 unit

=cut
sub unit{
    my $self = shift;
    return $self->{'unit'};
}

=head2 decom

=cut
sub decom{
    my $self = shift;
    
    my $res;
    if($self->type() eq 'vrf'){

        foreach my $peer (@{$self->peers()}){
            $peer->decom();
        }
        
        $res = OESS::DB::VRF::decom_endpoint(db => $self->{'db'}, vrf_endpoint_id => $self->vrf_endpoint_id());
        
    }else{

        $res = OESS::DB::Circuit::decom_endpoint(db => $self->{'db'}, circuit_endpoint_id => $self->circuit_endpoint_id());

    }

    return $res;

}

1;
