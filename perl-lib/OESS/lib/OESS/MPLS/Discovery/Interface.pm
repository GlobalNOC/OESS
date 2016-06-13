#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Discovery::Interface;

use OESS::Database;
use Log::Log4perl;
use Data::Dumper;

sub new{
    my $class = shift;
    my %args = (
        @_
        );

    my $self = \%args;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.Discovery.Interface');
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
    my $node_name = $params{'node'};
    my $interfaces = $params{'interfaces'};
    foreach my $interface (@$interfaces) {
	my $interface_id = $self->{'db'}->get_interface_id_by_names(node => $node_name, interface => $interface->{'name'});
	if (!defined($interface_id)) {
	    $self->{'logger'}->warn($self->{'db'}->{'error'});
	    return;
	}

	my $intf = $self->{'db'}->get_interface(interface_id => $interface_id);
	if (!defined($intf)) {
	    $self->{'logger'}->warn($self->{'db'}->{'error'});
	    return;
	}

	if ($intf->{'operational_state'} ne $interface->{'operational_state'}) {
	    my $result = $self->{'db'}->update_interface_operational_state(
		interface_id => $interface_id,
		operational_state => $interface->{'operational_state'}
		);
	    if (!defined($result)) {
		$self->{'logger'}->warn($self->{'db'}->{'error'});
		return;
	    }
	}
    }

    # all must have worked, return success
    return 1;
}

1;
