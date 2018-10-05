#!/usr/bin/perl

use strict;
use warnings;

package OESS::Endpoint;

use OESS::DB;
use OESS::Interface;
use OESS::Entity;
use OESS::Node;
use OESS::Peer;
use OESS::Entity;
use Data::Dumper;

=head2 new

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

    warn "Building endpoint from model\n";
    
    $self->{'inner_tag'} = $self->{'model'}->{'inner_tag'};
    $self->{'tag'} = $self->{'model'}->{'tag'};
    $self->{'bandwidth'} = $self->{'model'}->{'bandwidth'};
    $self->{cloud_account_id} = $self->{model}->{cloud_account_id};
    $self->{cloud_connection_id} = $self->{model}->{cloud_connection_id};


    if(defined($self->{'model'}->{'interface'})){
        $self->{'interface'} = OESS::Interface->new( db => $self->{'db'}, name => $self->{'model'}->{'interface'}, node => $self->{'model'}->{'node'});
        $self->{'entity'} = OESS::Entity->new( db => $self->{'db'}, interface_id => $self->{'interface'}->{'interface_id'}, vlan => $self->{'tag'});
    }else{
        $self->{'entity'} = OESS::Entity->new( db => $self->{'db'}, name => $self->{'model'}->{'entity'});
        $self->{'interface'} = $self->{'entity'}->interfaces()->[0];
    }


    if($self->{'type'} eq 'vrf'){
        $self->{'peers'} = ();
        foreach my $peer (@{$self->{'model'}->{'peerings'}}){
            push(@{$self->{'peers'}}, OESS::Peer->new( db => $self->{'db'}, model => $peer, vrf_ep_peer_id => -1));
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
    return $self->{'inner_tag'};
}

=head2 tag

=cut
sub tag{
    my $self = shift;
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
