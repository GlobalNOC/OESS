#!/usr/bin/perl

use strict;
use warnings;

package OESS::Endpoint;

use OESS::DB;
use OESS::Interface;
use OESS::Entity;
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

sub _build_from_model{
    my $self = shift;

    warn "Building endpoint from model\n";
    
    if(defined($self->{'model'}->{'interface'})){
        $self->{'interface'} = OESS::Interface->new( db => $self->{'db'}, name => $self->{'model'}->{'interface'}, node => $self->{'model'}->{'node'});
    }else{
        $self->{'interface'} = OESS::Entity->new( db => $self->{'db'}, name => $self->{'model'}->{'entity'})->interfaces()->[0];
    }
    $self->{'inner_tag'} = $self->{'model'}->{'inner_tag'};
    $self->{'tag'} = $self->{'model'}->{'tag'};
    $self->{'bandwidth'} = $self->{'model'}->{'bandwidth'};

    if($self->{'type'} eq 'vrf'){
        $self->{'peers'} = ();
        foreach my $peer (@{$self->{'model'}->{'peerings'}}){
            push(@{$self->{'peers'}}, OESS::Peer->new( db => $self->{'db'}, model => $peer, vrf_ep_peer_id => -1));
        }
    }

}

sub create{
    my $self = shift;

    my $endpoint_id = OESS::DB::Endpoint::create( db => $self->{'db'}, model => $self->_to_hash());

    return $endpoint_id;
}

sub to_hash{
    my $self = shift;
    my $obj;

    $obj->{'interface'} = $self->interface()->to_hash();
    $obj->{'node'} = $self->interface()->node()->to_hash();
    $obj->{'inner_tag'} = $self->inner_tag();
    $obj->{'tag'} = $self->tag();
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

    $self->{'inner_tag'} = $hash->{'inner_tag'};
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

sub inner_tag{
    my $self = shift;
    return $self->{'inner_tag'};
}

sub tag{
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
