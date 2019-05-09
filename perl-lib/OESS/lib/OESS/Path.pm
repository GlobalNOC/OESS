use strict;
use warnings;

package OESS::Path;

use Data::Dumper;

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

1;
