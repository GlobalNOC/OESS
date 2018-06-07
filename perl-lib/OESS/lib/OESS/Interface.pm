#!/usr/bin/perl

use strict;
use warnings;

package OESS::Interface;

use OESS::DB::Interface;

sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.Interface");

    my %args = (
        interface_id => undef,
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

    $self->{'name'} = $hash->{'name'};
    $self->{'interface_id'} = $hash->{'interface_id'};
    $self->{'node'} = $hash->{'node'};
    $self->{'description'} = $hash->{'description'};
    $self->{'operational_state'} = $hash->{'operational_state'};
    

}

sub to_hash{
    my $self = shift;
    
    return { name => $self->name(),
             description => $self->description(),
             interface_id => $self->interface_id(),
             node_id => $self->node()->node_id(),
             node => $self->node()->name() 
    };
}

sub _fetch_from_db{
    my $self = shift;

    my $info = OESS::DB::Interface::fetch(db => $self->{'db'}, interface_id => $self->{'interface_id'});
    $self->from_hash($info);
}

sub update_db{
    my $self = shift;

}

sub name{
    my $self = shift;
    return $self->{'name'};
}

sub description{
    my $self = shift;
    return $self->{'description'};
    
}

sub port_number{

}

sub interface_id{
    my $self = shift;
    return $self->{'interface_id'};

}

sub operational_state{

}

sub role{

}

sub node{
    my $self = shift;
    return $self->{'node'};
}

sub workgroup{
    
}

sub vlan_tag_range{

}

sub mpls_vlan_tag_range{

}


1;

