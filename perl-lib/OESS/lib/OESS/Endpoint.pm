#!/usr/bin/perl

use strict;
use warnings;

package OESS::Endpoint;

use OESS::DB;
use OESS::Interface;
use OESS::Node;
use OESS::Peer;
use Data::Dumper;

sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.Endpoint");

    my %args = (
        details => undef,
        vrf_id => undef,
        db => undef,
        just_display => 0,
        link_status => undef,
        @_
        );

    my $self = \%args;

    bless $self, $class;

    $self->{'logger'} = $logger;

    if(!defined($self->{'db'})){
        $self->{'logger'}->error("No Database Object specified");
        return;
    }

    $self->_fetch_from_db();

    return $self;

}

sub to_hash{
    my $self = shift;
    my $obj;

    $obj->{'interface'} = $self->interface()->to_hash();
    $obj->{'node'} = $self->interface()->node()->to_hash();
    $obj->{'vlan'} = $self->vlan();
    $obj->{'bandwidth'} = $self->bandwidth();

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
    return $obj;

}

sub from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{'bandwidth'} = $hash->{'bandwidth'};
    $self->{'interface'} = $hash->{'interface'};

    if($self->{'type'} eq 'vrf'){
        $self->{'peers'} = $hash->{'peers'};
        $self->{'vrf_id'} = $hash->{'vrf_id'};
    }else{
        $self->{'circuit_id'} = $hash->{'circuit_id'};
    }

    $self->{'tag'} = $hash->{'tag'};
    $self->{'bandwidth'} = $hash->{'bandwidth'};
    
}

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


sub interface{
    my $self = shift;
    return $self->{'interface'};
}

sub node{
    my $self = shift;
    return $self->{'interface'}->node();
}

sub type{
    my $self = shift;
    $self->{'type'};
}

sub peers{
    my $self = shift;
    if(!defined($self->{'peers'})){
        return [];
    }
    return $self->{'peers'};
}

sub vlan{
    my $self = shift;
    return $self->{'tag'};
}

sub bandwidth{
    my $self = shift;
    return $self->{'bandwidth'};
}

sub vrf_endpoint_id{
    my $self = shift;
    return $self->{'vrf_endpoint_id'};
}

sub vrf_id{
    my $self = shift;
    return $self->{'vrf_id'};
}

sub circuit_id{
    my $self = shift;
    return $self->{'circuit_id'};
}

sub circuit_endpoint_id{
    my $self = shift;
    return $self->{'circuit_endpoint_id'};
}

1;
