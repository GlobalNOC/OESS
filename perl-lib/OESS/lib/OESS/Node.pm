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

sub _from_hash{

}

sub _to_hash{

}

sub _fetch_from_db{

}

1;
