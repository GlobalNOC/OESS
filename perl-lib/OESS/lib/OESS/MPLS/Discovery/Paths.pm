#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Discovery::Paths;

use Data::Dumper;
use Log::Log4perl;
use AnyEvent;
use List::MoreUtils qw(uniq);

use OESS::Database;
use OESS::DB;
use OESS::DB::Link;
use OESS::DB::Path;
use OESS::Circuit;
use OESS::L2Circuit;
use OESS::Link;
use OESS::Path;

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
    if (!defined $self->{db2}) {
        $self->{db2} = new OESS::DB(config => $self->{config});
    }

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

    $self->{'logger'}->debug(Dumper($circuit_lsps));
    $self->{'logger'}->debug(Dumper($lsp_paths));

    my $ip_links = {}; # Map from IPAddress to Link
    $self->{db2}->start_transaction;

    my $links_db = OESS::DB::Link::fetch_all(db => $self->{db2});
    foreach my $link (@{$links_db}){
        $ip_links->{$link->{ip_a}} = new OESS::Link(db => $self->{db2}, model => $link);
        $ip_links->{$link->{ip_z}} = new OESS::Link(db => $self->{db2}, model => $link);
    }

    foreach my $circuit_id (keys %{$circuit_lsps}) {
        my $links = {};

        foreach my $lsp (@{$circuit_lsps->{$circuit_id}}) {
            if (!defined $lsp_paths->{$lsp}) {
                # Circuit is associated with an LSP that we don't have
                # a list of hops for; Continue on without it.
                $self->{'logger'}->warn("LSP missing path data.");
                next;
            }

            foreach my $ip (@{$lsp_paths->{$lsp}}) {
                my $link = $ip_links->{$ip};
                if (defined $link) {
                    # This if check removes any undef elements. It's
                    # possible this may happen when multiple LSPs are
                    # configured on the same port.
                    $links->{$link->{link_id}} = $link;
                }
            }
        }
        my @ckt_path = map { $links->{$_} } keys(%$links);

        my $ckt = new OESS::L2Circuit(db => $self->{db2}, circuit_id => $circuit_id);
        next if !defined $ckt;
        $ckt->load_paths;

        my $pri = $ckt->path(type => 'primary');
        my $pri_active = 0;
        my $dft = $ckt->path(type => 'tertiary');

        if (defined $pri) {
            my $equal = $pri->compare_links(\@ckt_path);
            if ($equal) {
                if ($pri->state eq 'active') {
                    # PASS
                } else {
                    OESS::DB::Path::update(db => $self->{db2}, path => { path_id => $pri->path_id, state => 'active' });
                }
                $pri_active = 1;
            } else {
                if ($pri->state eq 'active') {
                    OESS::DB::Path::update(db => $self->{db2}, path => { path_id => $pri->path_id, state => 'deploying' });
                }
            }
        }

        # $dft will be undefined on circuits with static paths until
        # that path encounters a failure.
        if ($pri_active) {
            if (defined $dft && $dft->state eq 'active') {
                OESS::DB::Path::update(db => $self->{db2}, path => { path_id => $dft->path_id, state => 'deploying' });
            } else {
                # If primary is active and a default is undef then the
                # primary path has yet to experience a failure and no
                # default path has been created. Do nothing for now.
            }
        } else {
            if (!defined $dft) {
                # If primary is inactive and a default is undef then
                # the primary path has experienced its first
                # failure. Create and populate a default path. This
                # will populate the Circuit's currently active path.

                $dft = new OESS::Path(db => $self->{db2}, model => {
                    mpls_type => 'loose',
                    type      => 'tertiary',
                    state     => 'active'
                });
                foreach my $link (@ckt_path) {
                    $dft->add_link($link);
                }
                $dft->create(circuit_id => $ckt->circuit_id);
                next;
            }

            my $equal = $dft->compare_links(\@ckt_path);
            if ($equal) {
                if ($dft->state eq 'active') {
                    next;
                }
                OESS::DB::Path::update(db => $self->{db2}, path => { path_id => $dft->path_id, state => 'active' });
            } else {
                my $lookup = {};
                foreach my $link (@{$dft->links}) {
                    $lookup->{$link->link_id} = 1;
                }

                foreach my $link (@ckt_path) {
                    if (defined $lookup->{$link->link_id}) {
                        delete $lookup->{$link->link_id};
                        next;
                    }
                    $dft->add_link($link);
                }

                foreach my $link_id (keys %$lookup) {
                    $dft->remove_link($link_id);
                }

                $dft->state('active');
                $dft->update;
            }
        }
    }

    $self->{db2}->commit;
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
