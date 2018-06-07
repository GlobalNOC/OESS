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

sub _from_hash{
    my $self = shift;

    

}

sub _to_hash{
    my $self = shift;
    
}

sub _fetch_from_db{
    my $self = shift;

}

sub update_db{
    my $self = shift;

}

sub name{

}

sub description{

}

sub port_number{

}

sub interface_id{

}

sub operational_state{

}

sub role{

}

sub node{

}

sub workgroup{

}

sub vlan_tag_range{

}

sub mpls_vlan_tag_range{

}


1;

