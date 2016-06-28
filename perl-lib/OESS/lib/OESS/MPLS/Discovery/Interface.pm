#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Discovery::Interface;

use OESS::Database;
use Log::Log4perl;

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
    
    $self->{'db'}->_start_transaction();
    
    foreach my $interface (@$interfaces) {
	my $interface_id = $self->{'db'}->get_interface_id_by_names(node => $node_name, interface => $interface->{'name'});
	if (!defined($interface_id)) {
	    my $node = $self->{'db'}->get_node_by_name(name => $node_name);
	    if (!defined($node)) {
		$self->{'logger'}->warn($self->{'db'}->{'error'});
		$self->{'db'}->_rollback();
		return;
	    }

	    my $res = $self->{'db'}->add_or_update_interface(
		node_id => $node->{'node_id'},
		name => $interface->{'name'},
		operational_state => $interface->{'operational_state'},
		admin_state => $interface->{'admin_state'},
		description => $interface->{'description'},
		);
	    if (!defined($res)) {
		$self->{'logger'}->warn($self->{'db'}->{'error'});
		$self->{'db'}->_rollback();
		return;
	    } else {
		next;
	    }
	}

	my $intf = $self->{'db'}->get_interface(interface_id => $interface_id);
	if (!defined($intf)) {
	    $self->{'logger'}->warn($self->{'db'}->{'error'});
	    $self->{'db'}->_rollback();
	    return;
	}

	if ($intf->{'operational_state'} ne $interface->{'operational_state'}) {
	    my $result = $self->{'db'}->update_interface_operational_state(
		interface_id => $interface_id,
		operational_state => $interface->{'operational_state'}
		);
	    if (!defined($result)) {
		$self->{'logger'}->warn($self->{'db'}->{'error'});
		$self->{'db'}->_rollback();
		return;
	    }
	}
    }

    # all must have worked, commit and return success
    $self->{'db'}->_commit();
    return 1;
}

1;
