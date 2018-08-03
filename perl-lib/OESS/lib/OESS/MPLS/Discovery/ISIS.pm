#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Discovery::ISIS;

use OESS::Database;
use Log::Log4perl;
use AnyEvent;

=head2 new

    creates a new OESS::MPLS::Discovery::ISIS object

=cut

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

=head2 process_results

    takes the results from show isis adj or equivilent
    and returns the current direct adjacencies on the network

=cut

sub process_results{
    my $self = shift;
    my %params = @_;

    my $isis = $params{'isis'};
    if(!defined($isis)){
	$self->{'logger'}->error("Error fetching current links from the network...");
	return;
    }
    my $adjacencies = $self->_process_adjacencies($isis);

    return $adjacencies;
}

sub _process_adjacencies{
    my $self = shift;
    my $isis = shift;
    
    # A hash mapping source node to destination node.
    # {
    #   'src': {
    #       'local_intf': {
    #         'operational_state': '',
    #         'local_intf':  '',
    #         'local_node':  '',
    #         'remote_node': '',
    #         'remote_ip':   '',
    #         'remote_ipv6': ''
    #   }
    # }
    my $adjacencies = {};

    foreach my $node (keys %{$isis}) {
	if (!defined $adjacencies->{$node}) {
	    $adjacencies->{$node} = {};
	}

        foreach my $adj (@{$isis->{$node}->{'results'}}) {
            my $intf = $adj->{'interface_name'};

            my $a = {
                operational_state => $adj->{'operational_state'},
                local_node => $node,
                local_intf => $intf,
                remote_node => $adj->{'remote_system_name'},
                remote_ip   => $adj->{'ip_address'},
                remote_ipv6 => $adj->{'ipv6_address'}
            };

            $adjacencies->{$node}->{$intf} = $a;
        }
    }

    return $adjacencies;
}

1;
