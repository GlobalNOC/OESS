use strict;
use warnings;

package OESS::Path;

use Data::Dumper;
use Graph::Directed;

use OESS::DB::Link;
use OESS::DB::Path;
use OESS::Link;

=head1 OESS::Path

    use OESS::Path;

=cut

=head2 new

    my $path = new OESS::Path(
        db      => $db,
        path_id => 100
    );

    # or

    my $path = new OESS::Path(
        model => {
            circuit_id => 3011,
            path_id    => 12,
            mpls_type  => 'strict',
            type       => 'primary',
            state      => 'active'
        }
    );

=cut
sub new {
    my $that  = shift;
    my $class = ref($that) || $that;

    my $self = {
        db => undef,
        path_id => undef,
        logger => Log::Log4perl->get_logger("OESS.Path"),
        @_
    };
    bless $self, $class;

    if (!defined $self->{db} && !defined $self->{model}) {
        $self->{logger}->error("Couldn't create Path: Arguments `db` and `model` are both missing.");
        return;
    }

    if (defined $self->{db} && defined $self->{path_id}) {
        eval {
            $self->{model} = OESS::DB::Path::fetch(
                db => $self->{db},
                path_id => $self->{path_id}
            );
        };
        if ($@) {
            $self->{logger}->error("Couldn't create Path: $@");
            return;
        }
    }

    if (!defined $self->{model}) {
        $self->{logger}->error("Couldn't create Path.");
        return;
    }
    $self->from_hash($self->{model});

    return $self;
}

=head2 from_hash

=cut
sub from_hash {
    my $self = shift;
    my $hash = shift;

    $self->{path_id} = $hash->{path_id};
    $self->{circuit_id} = $hash->{circuit_id};
    $self->{type} = $hash->{type};
    $self->{mpls_type} = $hash->{mpls_type};
    $self->{state} = $hash->{state};

    return 1;
}

=head2 to_hash

=cut
sub to_hash {
    my $self = shift;

    my $hash = {
        path_id => $self->path_id,
        circuit_id => $self->circuit_id,
        type => $self->type,
        mpls_type => $self->mpls_type,
        state => $self->state,
    };

    if (defined $self->{links}) {
        $hash->{links} = [];
        foreach my $link (@{$self->{links}}) {
            push @{$hash->{links}}, $link->to_hash;
        }
    }
    return $hash;
}

=head2 create

=cut
sub create {
    my $self = shift;
    my $args = {
        circuit_id => undef,
        @_
    };

    if (!defined $self->{db}) {
        $self->{'logger'}->error("Couldn't create Link: DB handle is missing.");
        return (undef, "Couldn't create Link: DB handle is missing.");
    }

    return (undef, 'Required argument `circuit_id` is missing.') if !defined $args->{circuit_id};
    $self->{circuit_id} = $args->{circuit_id};

    # TODO - Validate Path

    # TODO - Save Path
    my ($path_id, $path_err) = OESS::DB::Path::create(
        db => $self->{db},
        model => {
            circuit_id => $self->circuit_id,
            state => $self->state,
            type => $self->type,
            mpls_type => $self->mpls_type
        }
    );
    if (defined $path_err) {
        return (undef, $path_err);
    }

    foreach my $link (@{$self->{links}}) {

        my ($path_lk, $path_lk_err) = OESS::DB::Path::add_link(
            db             => $self->{db},
            link_id        => $link->link_id,
            path_id        => $path_id,
            interface_a_id => $link->interface_a_id,
            interface_z_id => $link->interface_z_id
        );
        if (defined $path_lk_err) {
            return (undef, $path_lk_err);
        }
    }

    $self->{circuit_id} = $args->{circuit_id};
    $self->{path_id} = $path_id;

    return ($path_id, undef);
}

=head2 add_link

=cut
sub add_link {
    my $self = shift;
    my $link = shift;

    push @{$self->{links}}, $link;
}

=head2 load_links

=cut
sub load_links {
    my $self = shift;

    my ($link_datas, $error) = OESS::DB::Link::fetch_all(
        db => $self->{db},
        path_id => $self->path_id
    );
    if (defined $error) {
        $self->{logger}->error($error);
    }

    $self->{links} = [];
    foreach my $data (@$link_datas) {
        push @{$self->{links}}, new OESS::Link(db => $self->{db}, model => $data);
    }

    return 1;
}

=head2 path_id

=cut
sub path_id {
    my $self = shift;
    return $self->{path_id};
}

=head2 circuit_id

=cut
sub circuit_id {
    my $self = shift;
    return $self->{circuit_id};
}

=head2 type

=cut
sub type {
    my $self = shift;
    return $self->{type};
}

=head2 mpls_type

=cut
sub mpls_type {
    my $self = shift;
    return $self->{mpls_type};
}

=head2 state

=cut
sub state {
    my $self = shift;
    my $state = shift;
    if (defined $state) {
        $self->{state} = $state;
    }
    return $self->{state};
}

=head2 connects

    my $ok = $self->connects($node_a_id, $node_z_id);

connects returns C<1> if C<$node_a_id> connects to C<$node_z_id>
through the Links of this Path.

=cut
sub connects {
    my $self      = shift;
    my $node_a_id = shift;
    my $node_z_id = shift;

    my $g = new Graph::Undirected;
    foreach my $link (@{$self->{links}}) {
        $g->add_edge($link->node_a_id, $link->node_z_id);
    }

    # Returns list of nodes including $node_a_id and $node_z_id, so if
    # the length of the path is less than two no path exists. In
    # theory if the same node is passed twice a list of size one would
    # be returned, but static paths must include at least one link so
    # this case doesn't apply to us.
    my @path = $g->SP_Dijkstra($node_a_id, $node_z_id);
    if (@path < 2) {
        return 0;
    }

    return 1;
}

1;
