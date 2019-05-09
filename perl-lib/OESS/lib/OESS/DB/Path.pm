use strict;
use warnings;

package OESS::DB::Path;

use Data::Dumper;

=head1 OESS::DB::Path

=cut

=head2 create

    my $id = OESS::DB::Path::create(
        db => $db,
        model => {
            circuit_id => 1,
            state      => 'active',
            type       => 1,
            mpls_type  => 'loose'
        }
    );

=cut
sub create {
    my $args = {
        db => undef,
        model => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `model` is missing.') if !defined $args->{model};

    my $q1 = "
        INSERT INTO path (circuit_id, path_type, path_state, mpls_path_type)
        VALUES (?,?,?,?)
    ";

    my $q2 = "
        INSERT INTO path_instantiation (path_id, path_state, start_epoch, end_epoch)
        VALUES (?,?,UNIX_TIMESTAMP(NOW()),-1)
    ";

    my $path_id = $args->{db}->execute_query($q1, [
        $args->{model}->{circuit_id},
        $args->{model}->{state},
        $args->{model}->{type},
        $args->{model}->{mpls_type}
    ]);
    if (!defined $path_id) {
        return (undef, $args->{db}->get_error);
    }

    my $path_instantiation_id = $args->{db}->execute_query($q2, [
        $path_id,
        $args->{model}->{state}
    ]);
    if (!defined $path_instantiation_id) {
        return (undef, $args->{db}->get_error);
    }

    return ($path_id, undef);
}

=head2 fetch

    my $path = OESS::DB::Path::fetch(db => $conn, path_id => 1);

fetch returns Path C<path_id> from database C<db>.

=cut
sub fetch {
    my $args = {
        db => undef,
        path_id => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `path_id` is missing.') if !defined $args->{path_id};

    my $q = "
        SELECT path.path_id, path.circuit_id, path.path_state as state,
               path.mpls_path_type as mpls_type, path.path_type as type
        FROM path
        JOIN path_instantiation ON path.path_id=path_instantiation.path_id
        WHERE path.path_id=? AND path_instantiation.end_epoch=-1
    ";
    my $path = $args->{db}->execute_query($q, [
        $args->{path_id}
    ]);
    if (!defined $path) {
        return (undef, "Couldn't find Path $args->{path_id}: " . $args->{db}->get_error);
    }
    if (!defined $path->[0]) {
        return (undef, "Couldn't find Path $args->{path_id}.");
    }

    return ($path->[0], undef);
}

=head2 fetch_all

    my $acl = OESS::DB::Patch::fetch_all(
        db         => $conn,
        path_id    => 1,     # Optional
        circuit_id => 1,     # Optional
        type       => 1,     # Optional
        state      => 1      # Optional
    );

fetch_all returns a list of all Paths from database C<db> filtered by
C<path_id>, C<circuit_id>, C<type>, and C<state>.

=cut
sub fetch_all {
    my $args = {
        db => undef,
        path_id => undef,
        circuit_id => undef,
        type => undef,
        mpls_type => undef,
        state => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};

    my $params = [];
    my $values = [];

    if (defined $args->{path_id}) {
        push @$params, 'path.path_id=?';
        push @$values, $args->{path_id};
    }
    if (defined $args->{circuit_id}) {
        push @$params, 'path.circuit_id=?';
        push @$values, $args->{circuit_id};
    }
    if (defined $args->{type}) {
        push @$params, 'path.path_type=?';
        push @$values, $args->{type};
    }
    if (defined $args->{mpls_type}) {
        push @$params, 'path.mpls_path_type=?';
        push @$values, $args->{mpls_type};
    }
    if (defined $args->{state}) {
        push @$params, 'path.path_state=?';
        push @$values, $args->{state};
    }

    push @$params, 'path_instantiation.end_epoch=?';
    push @$values, -1;

    my $where = (@$params > 0) ? 'WHERE ' . join(' AND ', @$params) : '';

    my $q = "
        SELECT path.path_id, path.circuit_id, path.path_state as state,
               path.mpls_path_type as mpls_type, path.path_type as type
        FROM path
        JOIN path_instantiation ON path.path_id=path_instantiation.path_id
        $where
    ";

    my $paths = $args->{db}->execute_query($q, $values);
    if (!defined $paths) {
        return (undef, "Couldn't find Paths: " . $args->{db}->get_error);
    }

    return $paths;
}

1;
