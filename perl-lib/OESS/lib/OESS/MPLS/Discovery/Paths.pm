#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Discovery::Paths;

use OESS::Database;
use OESS::Circuit;
use Log::Log4perl;
use AnyEvent;

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

    if(!defined($params{'lsp_interfaces'})){
        $self->{'logger'}->error("process_results: lsp_interfaces not defined");
        return 0;
    }

    if(!defined($params{'node_id'})){
        $self->{'logger'}->error("process_results: node_id not defined");
        return 0;
    }

    return $self->_process_paths(
        lsp_paths      => $params{'lsp_paths'},
        lsp_interfaces => $params{'lsp_interfaces'},
        node_id        => $params{'node_id'},
    );
}


sub _process_paths{
    my $self = shift;
    my %params = @_;

    my $lsp_paths = $params{'lsp_paths'};           # map from LSP name to list of link-endpoint IP addresses
    my $lsp_interfaces = $params{'lsp_interfaces'}; # map from LSP name to list of (interface, VLAN tag) pairs using that LSP
    my $node_id = $params{'node_id'};               # node ID of the node in question

    my %links;
    my $links_db = $self->{'db'}->get_current_links( mpls => 1 );
    foreach my $link (@{$links_db}){
        my $ip_a = $link->{'ip_a'};
        my $ip_z = $link->{'ip_z'};

        $links{$ip_a} = $link;
        $links{$ip_z} = $link;
    }

    my %nodes;
    my $nodes_db = $self->{'db'}->get_current_nodes( mpls => 1);
    foreach my $node (@$nodes_db){
        $nodes{$node->{'node_id'}} = $node;
    }

    warn "Processing the paths into links!\n";

    foreach my $lsp (keys %{$lsp_paths}){
        my @lsp_links = map { $links{$_} }, @{$lsp_paths->{$lsp}};
        foreach my $endpoint (@{$lsp_interfaces->{$lsp}}) {
            my $interface = $endpoint->[0];
            my $vlan_tag = $endpoint->[1];

            my $db_circuit = $self->{'db'}->get_circuit_by_nodeid_interfacename_vlan(
                node_id   => $node_id,
                interface => $interface,
                vlan      => $vlan_tag
            );

            # [syncing up the path in the DB goes here]
        }
    }



# Above should be OK (modulo bugs), below needs to be revised/mapped into new scheme of things:
#
# Former implementation, pre-4296:
#
#    foreach my $dest (keys %{$paths}){
#        my @links;
#
#        foreach my $addr (@{$paths->{$dest}->{'path'}}){
#            if(!defined($links{$addr})){
#                warn "PROBLEM HERE!!!\n";
#                $self->{'logger'}->error("NO link found with address: " . $addr);
#                next;
#            }
#            push(@links,$links{$addr});
#        }
#
#        $paths->{$dest}->{'links'} = \@links;
#    }
#
#    foreach my $ckt (@{$self->get_circuits( node_id => $params{'node_id'} )}){
#        #TODO: THIS WONT WORK FOR MP CIRCUITS
#        next if !defined($ckt);
#        my $eps = $ckt->get_endpoints();
#        foreach my $ep (@$eps){
#            next if ($ep->{'node_id'} == $node_id );
#            warn Data::Dumper::Dumper($node_id{$ep->{'node_id'}});
#            my $links = $paths->{$node_id{$ep->{'node_id'}}->{'loopback_address'}}->{'links'};
#            warn "LINKS: " . Data::Dumper::Dumper($links);
#            $ckt->change_mpls_path( links => $paths->{$node_id{$ep->{'node_id'}}->{'loopback_address'}}->{'links'} );        
#        }
#    }
    
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
