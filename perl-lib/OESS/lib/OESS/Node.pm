#!/usr/bin/perl

use strict;
use warnings;

package OESS::Node;

sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.Node");

    my %args = (
        node_id => undef,
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

    $self->_fetch_from_db();

    return $self;
}

sub from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{'node_id'} = $hash->{'node_id'};
    $self->{'name'} = $hash->{'name'};
    $self->{'latitude'} = $hash->{'latitude'};
    $self->{'longitude'} = $hash->{'longitude'};
    
}

sub to_hash{
    my $self = shift;
    my $obj = { node_id => $self->{'node_id'},
                name => $self->{'name'},
                latitude => $self->{'latitude'},
                longitude => $self->{'longitude'}};

    return $obj;
}

sub _fetch_from_db{
    my $self = shift;
    my $db = $self->{'db'};
    my $hash = OESS::DB::Node::fetch(db => $db, node_id => $self->{'node_id'});
    $self->from_hash($hash);
}

sub node_id{
    my $self = shift;
    return $self->{'node_id'};
}

sub name{
    my $self = shift;
    return $self->{'name'};
}

sub interfaces{
    my $self = shift;
    my $interfaces = shift;
    
    if(defined($interfaces)){

    }else{
       
        if(!defined($self->{'interfaces'})){
            my $interfaces = OESS::DB::Node::get_interfaces(db => $self->{'db'}, node_id => $self->{'node_id'});
            $self->{'interfaces'} = $interfaces;
        }
        
        return $self->{'interfaces'};
    }
}

1;
