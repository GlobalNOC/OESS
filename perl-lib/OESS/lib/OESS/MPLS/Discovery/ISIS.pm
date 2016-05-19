#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Discovery::ISIS;

use OESS::Database;

use Log::Log4perl;
use AnyEvent;

sub new{
    my $class = shift;
    my %args = (
        @_
        );

    my $self = \%args;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.Discovery.ISIS');
    bless $self, $class;

    if(!defined($self->{'db'})){
	
	if(!defined($self->{'config'})){
	    $self->{'config'} = "/etc/oess/database.xml";
	}
	
	$self->{'db'} = OESS::Database->new( config_file => $self->{'config'} );
	
    }

    die if(!defined($self->{'db'}));

    return $self;
}

sub process_results{
    my $self = shift;
    my %params = @_;

    return 1;
}

1;
