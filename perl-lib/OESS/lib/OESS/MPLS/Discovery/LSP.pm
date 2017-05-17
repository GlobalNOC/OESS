#!/usr/bin/perl                                                                                                                                                                                    
use strict;
use warnings;

package OESS::MPLS::Discovery::LSP;
use Data::Dumper;
use OESS::Database;

use Log::Log4perl;
use AnyEvent;

my $lsps = {};

=head2 new

creates a new OESS::MPLS::Discovery LSP ojbect

=cut

sub new{
    my $class = shift;
    my %args = (
        @_
        );

    my $self = \%args;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.Discovery');
    bless $self, $class;

    if(!defined($self->{'config'})){
        $self->{'config'} = "/etc/oess/database.xml";
    }

#    $self->{'db'} = OESS::Database->new( config_file => $self->{'config'} );

#    die if(!defined($self->{'db'}));

    return $self;
}

=head2 process_results

does nothing?  not used?

=cut

sub process_results{
    my $self = shift;
    my %params = @_;

    return 1;
}

=head2 get_lsps_per_node

    finds all of the LSPs on the node

=cut

sub get_lsps_per_node {
    my $self = shift;
    my $data = shift;


    foreach my $top (%{$data}){

	foreach my $hostname (keys ( %{$data->{$top}} ) ) {

	    my $state = $data->{$top}->{$hostname}->{'pending'};
	    my $results = $data->{$top}->{$hostname}->{'results'};
	    $lsps->{$hostname} = {};

	    foreach my $session_type (@$results){
		my $sessions = ($session_type->{'sessions'});

		foreach my $sessionsa (@$sessions){
		    my $name  = $sessionsa ->{'name'};
		$lsps->{$name}->{$hostname} = $sessionsa;
		}
	    }
	    print Dumper($lsps);
	    return $lsps;
	}
    
    }


}

1;
