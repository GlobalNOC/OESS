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

    my $isis = $params{'isis'};
    if(!defined($isis)){
	$self->{'logger'}->error("Error fetching current links from the network...");
	return;
    }
    my $adjacencies = $self->_process_adjacencies2($isis);

    return $adjacencies;
}

sub _process_adjacencies{
    my $self = shift;
    my $isis = shift;
    
    my $adjacencies = {};
    
    foreach my $node (keys(%{$isis})){
	if(!defined($adjacencies->{$node})){
	    $adjacencies->{$node} = {};
	}

        foreach my $adj (@{$isis->{$node}->{'results'}}){
	    if(!defined($adjacencies->{$adj->{'remote_system_name'}})){
		$adjacencies->{$adj->{'remote_system_name'}} = {};
	    }
	    if(!defined($adjacencies->{$node}{$adj->{'remote_system_name'}})){
		$adjacencies->{$node}{$adj->{'remote_system_name'}} = {operational_state => $adj->{'operational_state'},
								       node_a => {node => $node,
										  interface_name => $adj->{'interface_name'},
								       },
								       node_z => {node => $adj->{'remote_system_name'},
										  ip_address => $adj->{'ip_address'},
										  ipv6_address => $adj->{'ipv6_address'}}};
		
		$adjacencies->{$adj->{'remote_system_name'}}{$node} = {operational_state => $adj->{'operational_state'},
								       node_z => {node => $node,
										  interface_name => $adj->{'interface_name'},
								       },
								       node_a => {node => $adj->{'remote_system_name'},
										  ip_address => $adj->{'ip_address'},
										  ipv6_address => $adj->{'ipv6_address'}}};
	    }else{
		#we already found it update it with the missing info from the other side!
		$adjacencies->{$adj->{'remote_system_name'}}{$node}{'node_a'}{'ip_address'} = $adj->{'ip_address'};
		$adjacencies->{$adj->{'remote_system_name'}}{$node}{'node_a'}{'ipv6_address'} = $adj->{'ipv6_address'};
		$adjacencies->{$adj->{'remote_system_name'}}{$node}{'node_z'}{'interface_name'} = $adj->{'interface_name'};
		$adjacencies->{$node}{$adj->{'remote_system_name'}}{'node_a'}{'interface_name'} = $adj->{'interface_name'};
		$adjacencies->{$node}{$adj->{'remote_system_name'}}{'node_a'}{'ip_address'} = $adj->{'ip_address'};
                $adjacencies->{$node}{$adj->{'remote_system_name'}}{'node_a'}{'ipv6_address'} = $adj->{'ipv6_address'};
	    }
        }
    }

    return $adjacencies;
}

sub _process_adjacencies2{
    my $self = shift;
    my $isis = shift;
    
    my $adjacencies = {};
    
    foreach my $node (keys %{$isis}) {
	if (!defined $adjacencies->{$node}) {
	    $adjacencies->{$node} = {};
	}

        foreach my $adj (@{$isis->{$node}->{'results'}}) {

            my $neighbor = $adj->{'remote_system_name'};
	    if (!defined $adjacencies->{$neighbor}) {
		$adjacencies->{$neighbor} = {};
	    }

	    if (!defined $adjacencies->{$node}{$neighbor}) {
		$adjacencies->{$node}{$neighbor} = { operational_state => $adj->{'operational_state'},
                                                     node_a => { node => $node,
                                                                 interface_name => $adj->{'interface_name'},
                                                               },
                                                     node_z => { node         => $neighbor,
                                                                 ip_address   => $adj->{'ip_address'},
                                                                 ipv6_address => $adj->{'ipv6_address'}
                                                               }
                                                   };
		
		$adjacencies->{$neighbor}{$node} = { operational_state => $adj->{'operational_state'},
                                                     node_a => { node => $neighbor,
                                                                 ip_address => $adj->{'ip_address'},
                                                                 ipv6_address => $adj->{'ipv6_address'}
                                                               },
                                                     node_z => { node => $node,
                                                                 interface_name => $adj->{'interface_name'}
                                                               }
                                                   };
	    } else {
		#we already found it update it with the missing info from the other side!
                $adjacencies->{$node}{$neighbor}{'node_a'}{'interface_name'} = $adj->{'interface_name'};
		$adjacencies->{$node}{$neighbor}{'node_z'}{'ip_address'}     = $adj->{'ip_address'};
                $adjacencies->{$node}{$neighbor}{'node_z'}{'ipv6_address'}   = $adj->{'ipv6_address'};

		$adjacencies->{$neighbor}{$node}{'node_a'}{'ip_address'}     = $adj->{'ip_address'};
		$adjacencies->{$neighbor}{$node}{'node_a'}{'ipv6_address'}   = $adj->{'ipv6_address'};
		$adjacencies->{$neighbor}{$node}{'node_z'}{'interface_name'} = $adj->{'interface_name'};
	    }
        }
    }

    return $adjacencies;
}

1;
