#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Discovery::Paths;

use Data::Dumper;
use OESS::Database;
use OESS::Circuit;
use Log::Log4perl;
use AnyEvent;
use List::MoreUtils qw(uniq);

=head2 new

creates a new OESS::MPLS::Discovery::path object

=cut

sub new{
    my $class = shift;
    my %args = (
        @_
        );

    my $self = \%args;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.Discovery.Path');
    bless $self, $class;

    if(!defined($self->{'db'})){
	
	if(!defined($self->{'config'})){
	    $self->{'config'} = "/etc/oess/database.xml";
	}
	
	$self->{'db'} = OESS::Database->new( config_file => $self->{'config'} );
	
    }

    #die if(!defined($self->{'db'}));

    return $self;
}

=head2 process_results

=cut

sub process_results{
    my $self = shift;
    my %params = @_;

    if(!defined($params{'lsp_paths'})){
        $self->{'logger'}->error("process_results: lsp_paths not defined");
        return 0;
    }

    if(!defined($params{'circuit_lsps'})){
        $self->{'logger'}->error("process_results: circuit_lsps not defined");
        return 0;
    }

    return $self->_process_paths(
        lsp_paths    => $params{'lsp_paths'},
        circuit_lsps => $params{'circuit_lsps'},
    );
}


sub _process_paths{
    my $self = shift;
    my %params = @_;

    my $circuit_lsps = $params{'circuit_lsps'}; # map from circuit ID to list of LSPs making up the path of the circuit
    my $lsp_paths = $params{'lsp_paths'};       # map from LSP name to list of link-endpoint IP addresses

    $self->{'logger'}->error(Dumper($circuit_lsps));
    $self->{'logger'}->error(Dumper($lsp_paths));

    my %ip_links; # Map from IP address to link_id
    my %links_by_id; # Map from link_id to link

    $self->{db}->_start_transaction();

    my $links_db = $self->{'db'}->get_current_links(type => 'mpls');
    foreach my $link (@{$links_db}){
        my $ip_a = $link->{'ip_a'};
        my $ip_z = $link->{'ip_z'};
        my $link_id = $link->{'link_id'};

        $ip_links{$ip_a} = $link_id;
        $ip_links{$ip_z} = $link_id;
        $links_by_id{$link_id} = $link;
    }

    warn "Processing the paths into links!\n";

    foreach my $circuit_id (keys %{$circuit_lsps}){
       my @ckt_path0; # list of (possibly duplicated) IP addresses making up the circuit
       foreach my $lsp (@{$circuit_lsps->{$circuit_id}}){
           if (!defined $lsp_paths->{$lsp}) {
               next;
           }
           push @ckt_path0, @{$lsp_paths->{$lsp}};
       }

       my @ckt_path1 = map { $ip_links{$_} } @ckt_path0;
       my @ckt_path2 = uniq @ckt_path1; # list of link_ids making up the circuit, without duplication
       my @ckt_path  = map { $links_by_id{$_} } @ckt_path2;

       # Remove any undef elements. It's possible this may happen when
       # multiple lsps are configured on the same port.
       @ckt_path = grep defined, @ckt_path;

       my $ckt = OESS::Circuit->new(db => $self->{'db'}, circuit_id => $circuit_id);
       my $ok = $ckt->update_mpls_path(links => \@ckt_path);
       if (!$ok) {
           $self->{db}->_rollback();
           return 0;
       }
    }

    $self->{db}->_commit();
    return 1;
}

=head2 get_circuits
    
    gets a list of circuits on an LSP

=cut

sub get_circuits{
    my $self = shift;
    my %params = @_;

    my @circuits;
    
    my $query = "select circuit.circuit_id from circuit join circuit_edge_interface_membership on circuit.circuit_id = circuit_edge_interface_membership.circuit_id join interface on circuit_edge_interface_membership.interface_id = interface.interface_id " .
        " where circuit.type = 'mpls' and circuit_edge_interface_membership.end_epoch = -1 and interface.node_id = " . $params{'node_id'};

    my $circuit_ids = $self->{'db'}->_execute_query($query, []);
    foreach my $ckt (@$circuit_ids){
        push(@circuits, OESS::Circuit->new( db => $self->{'db'},
                                            circuit_id => $ckt->{'circuit_id'} ));
    }

    return \@circuits;
    
}

1;
