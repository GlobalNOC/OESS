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
        links_to_add    => [],
        links_to_remove => [],
        @_
    };
    bless $self, $class;

    if (!defined $self->{db} && !defined $self->{model}) {
        $self->{logger}->error("Couldn't create Path: Arguments `db` and `model` are both missing.");
        return;
    }

    if (defined $self->{db} && defined $self->{path_id}) {
        eval {
            my ($model, $err) = OESS::DB::Path::fetch(
                db => $self->{db},
                path_id => $self->{path_id}
            );
            if (defined $err) {
                $self->{logger}->error("Couldn't load Path: $err");
            }
            $self->{model} = $model;
        };
        if ($@) {
            $self->{logger}->error("Couldn't create Path: $@");
            warn "Couldn't create Path: $@";
            return;
        }
    }

    if (!defined $self->{model}) {
        $self->{logger}->error("Couldn't create Path.");
        warn "Couldn't create Path.";
        warn Dumper($self->{model});
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

    # Figure out edges and path from side_a to side_z. In addition we
    # save node info for additional metadata which is used by our
    # device templates.
    my $g = new Graph::Undirected;
    my $n = {};
    foreach my $link (@{$self->{links}}) {
        $n->{$link->node_a_loopback} = {
            ip => $link->ip_a,
            node_loopback => $link->node_a_loopback,
            node_id => $link->node_a_id,
        };
        $n->{$link->node_z_loopback} = {
            ip => $link->ip_z,
            node_loopback => $link->node_z_loopback,
            node_id => $link->node_z_id,
        };

        $g->add_edge($link->node_a_loopback, $link->node_z_loopback);
    }
    my @path = $g->longest_path;

    my $edges = [];
    if (@path <= 1) {
        push @$edges, $path[0];
        push @$edges, $path[0];
    } else {
        push @$edges, $path[0];
        push @$edges, $path[@path - 1];
    }

    my $hash = {
        path_id => $self->path_id,
        circuit_id => $self->circuit_id,
        type => $self->type,
        mpls_type => $self->mpls_type,
        state => $self->state,
        details => {
            node_a => $n->{$edges->[0]},
            node_z => $n->{$edges->[1]},
            hops   => \@path
        }
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
        $self->{'logger'}->error("Couldn't create Path: DB handle is missing.");
        return (undef, "Couldn't create Path: DB handle is missing.");
    }

    return (undef, 'Required argument `circuit_id` is missing.') if !defined $args->{circuit_id};
    $self->{circuit_id} = $args->{circuit_id};

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
            path_id        => $path_id
        );
        if (defined $path_lk_err) {
            return (undef, $path_lk_err);
        }
    }

    $self->{circuit_id} = $args->{circuit_id};
    $self->{path_id} = $path_id;

    return ($path_id, undef);
}

=head2 update

    my $err = $path->update;
    $db->rollback if (defined $err);

update saves any changes made to this Path and maintains link
relationships based on calls to C<add_link> and C<remove_link>.

Note that any changes to the underlying Link objects will not be
propagated to the database by this method call. We maintain the object
structure, Path details, and Link-to-Path relationships. B<Nothing
else.>

=cut
sub update {
    my $self = shift;
    my $args = {
        @_
    };

    if (!defined $self->{db}) {
        $self->{'logger'}->error("Couldn't update Path: DB handle is missing.");
        return "Couldn't update Path: DB handle is missing.";
    }

    # Set state and create new path_instantiation
    my ($update_ok, $update_err) = OESS::DB::Path::update(
        db => $self->{db},
        path => { path_id => $self->path_id, state => $self->state }
    );
    return $update_err if (defined $update_err);

    foreach my $link_id (@{$self->{links_to_remove}}) {
        my ($decom_ok, $decom_err) = OESS::DB::Path::remove_link(
            db => $self->{db},
            link_id => $link_id,
            path_id => $self->path_id
        );
        return $decom_err if (defined $decom_err);
    }

    foreach my $link_id (@{$self->{links_to_add}}) {
        my ($create_ok, $create_err) = OESS::DB::Path::add_link(
            db => $self->{db},
            link_id => $link_id,
            path_id => $self->path_id
        );
        return $create_err if (defined $create_err);
    }

    return;
}

=head2 remove

    my $error = $path->remove;

remove decoms this Path in the database. This acts as a delete while
additionally maintaining the path's history.

=cut
sub remove {
    my $self = shift;

    if (!defined $self->{db}) {
        $self->{'logger'}->error("Couldn't remove Path: DB handle is missing.");
        return "Couldn't remove Path: DB handle is missing.";
    }

    my $error = OESS::DB::Path::remove(
        db => $self->{db},
        path_id => $self->path_id
    );
    return $error;
}


=head2 add_link

    $path->add_link($link);

add_link adds an C<OESS::Link> to this Path. If C<$link->{link_id}>
isn't defined, C<$this->update> will not save your data.

=cut
sub add_link {
    my $self = shift;
    my $link = shift;

    push @{$self->{links_to_add}}, $link->link_id;
    push @{$self->{links}}, $link;
}

=head2 remove_link

    $path->remove_link($link_id);

remove_link removes the link identified by C<$link_id> from this Path.

=cut
sub remove_link {
    my $self = shift;
    my $link_id = shift;

    my $new_links = [];
    foreach my $link (@{$self->{links}}) {
        if ($link->link_id == $link_id) {
            push @{$self->{links_to_remove}}, $link_id;
        } else {
            push @$new_links, $link;
        }
    }
    $self->{links} = $new_links;
}

=head2 links

=cut
sub links {
    my $self = shift;
    return $self->{links};
}

=head2 load_links

=cut
sub load_links {
    my $self = shift;

    my ($link_datas, $error) = OESS::DB::Path::get_links(
        db => $self->{db},
        path_id => $self->path_id
    );
    if (defined $error) {
        $self->{logger}->error($error);
        warn $error;
        return;
    }

    $self->{links} = [];
    foreach my $data (@$link_datas) {
        push @{$self->{links}}, new OESS::Link(db => $self->{db}, model => $data);
    }

    return 1;
}

=head2 compare_links

    my $eq = $path->compare_links($links);

compare_links returns C<1> if this C<OESS::Path>'s links are the same
as C<$links>, which is an array of C<OESS::Link>s. Otherwise C<0> is
returned.

=cut
sub compare_links {
    my $self = shift;
    my $links = shift;

    my $lookup = {};
    foreach my $link (@$links) {
        $lookup->{$link->link_id} = $link;
    }

    foreach my $link (@{$self->{links}}) {
        if (!defined $lookup->{$link->link_id}) {
            return 0;
        }
        delete $lookup->{$link->link_id};
    }

    if (keys(%$lookup) > 0) {
        return 0;
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

=head2 hops

    my $ok = $self->hops($loopback_a, $loopback_z);

hops returns a list of loopback addresses from C<$loopback_a> to
C<$loopback_z>.

=cut
sub hops {
    my $self = shift;
    my $loopback_a = shift;
    my $loopback_z = shift;

    my $g = new Graph::Undirected;
    foreach my $link (@{$self->{links}}) {
        $g->add_edge($link->node_a_loopback, $link->node_z_loopback);
    }

    my @path = $g->SP_Dijkstra($loopback_a, $loopback_z);
    return \@path;
}

1;
