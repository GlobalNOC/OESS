use strict;
use warnings;

package OESS::DB::Path;

use OESS::DB::Interface;
use OESS::DB::Link;

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
        $args->{model}->{type},
        $args->{model}->{state},
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

=head2 update

    my ($ok, $err) = OESS::DB::Path::update(
        db => $db,
        path => {
            path_id => 1,
            state   => 'active'
        }
    );

update modifies the C<path_state> in both the C<path> and
C<path_instantiation> tables.

=cut
sub update {
    my $args = {
        db  => undef,
        path => {},
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `path->path_id` is missing.') if !defined $args->{path}->{path_id};
    return (undef, 'Required argument `path->state` is missing.') if !defined $args->{path}->{state};

    my $params = [];
    my $values = [];

    if (defined $args->{path}->{state}) {
        push @$params, 'path.path_state=?';
        push @$values, $args->{path}->{state};
    }

    my $fields = join(', ', @$params);
    push @$values, $args->{path}->{path_id};

    my $ok = $args->{db}->execute_query(
        "UPDATE path SET $fields WHERE path_id=?",
        $values
    );
    if (!defined $ok) {
        return (undef, $args->{db}->get_error);
    }

    my $inst_ok = $args->{db}->execute_query(
        "UPDATE path_instantiation SET end_epoch=UNIX_TIMESTAMP(NOW()) WHERE path_id=? and end_epoch=-1",
        [$args->{path}->{path_id}]
    );
    if (!defined $inst_ok) {
        return (undef, $args->{db}->get_error);
    }

    my $q2 = "
        INSERT INTO path_instantiation (path_id, path_state, start_epoch, end_epoch)
        VALUES (?, ?, UNIX_TIMESTAMP(NOW()), -1)
    ";

    my $path_instantiation_id = $args->{db}->execute_query($q2, [
        $args->{path}->{path_id},
        $args->{path}->{state}
    ]);
    if (!defined $path_instantiation_id) {
        return (undef, $args->{db}->get_error);
    }

    return ($ok, undef);
}

=head2 remove

    my $error = OESS::DB::Path::remove(
        db => $db,
        path_id => 1
    );

remove sets the C<path_state> in both the C<path> and
C<path_instantiation> tables to 'decom' and sets the end_epoch to
none.

=cut
sub remove {
    my $args = {
        db  => undef,
        path_id => undef,
        @_
    };

    return 'Required argument `db` is missing.' if !defined $args->{db};
    return 'Required argument `path_id` is missing.' if !defined $args->{path_id};

    my $params = [];
    my $values = [];

    my $ok = $args->{db}->execute_query(
        "UPDATE path SET path_state='decom' WHERE path_id=?",
        [$args->{path_id}]
    );
    if (!defined $ok) {
        return $args->{db}->get_error;
    }

    my $inst_ok = $args->{db}->execute_query(
        "UPDATE path_instantiation SET end_epoch=UNIX_TIMESTAMP(NOW()), path_state='decom' WHERE path_id=? and end_epoch=-1",
        [$args->{path_id}]
    );
    if (!defined $inst_ok) {
        return $args->{db}->get_error;
    }

    return;
}

=head2 add_link

    my ($ok, $err) = OESS::DB::Path::add_link(
        path_id => 100,
        link_id => 100
    );
    warn $err if (defined $err);

add_link creates a new C<link_path_membership> identified by
C<path_id> and C<link_id>.

=cut
sub add_link {
    my $args = {
        db             => undef,
        link_id        => undef,
        path_id        => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `link_id` is missing.') if !defined $args->{link_id};
    return (undef, 'Required argument `path_id` is missing.') if !defined $args->{path_id};

    my ($link, $err) = OESS::DB::Link::fetch(
        db => $args->{db},
        link_id => $args->{link_id}
    );
    if (defined $err) {
        return (undef, $err);
    }

    my ($vlan_a_id, $err_a) = OESS::DB::Interface::get_available_internal_vlan(
        db => $args->{db},
        interface_id => $link->{interface_a_id}
    );
    if (defined $err_a) {
        return (undef, $err_a);
    }

    my ($vlan_z_id, $err_z) = OESS::DB::Interface::get_available_internal_vlan(
        db => $args->{db},
        interface_id => $link->{interface_z_id}
    );
    if (defined $err_z) {
        return (undef, $err_z);
    }

    my $q = "
        insert into link_path_membership (
            link_id, path_id, start_epoch, end_epoch,
            interface_a_vlan_id, interface_z_vlan_id
        ) VALUES (?, ?, UNIX_TIMESTAMP(NOW()), -1, ?, ?)
    ";
    my $res = $args->{db}->execute_query($q, [
        $args->{link_id},
        $args->{path_id},
        $vlan_a_id,
        $vlan_z_id
    ]);
    if (!defined $res) {
        return (undef, $args->{db}->get_error);
    }

    return ($res, undef);
}

=head2 remove_link

    my ($ok, $err) = OESS::DB::Path::remove_link(
        path_id => 100,
        link_id => 100
    );
    warn $err if (defined $err);

remove_link decoms the C<link_path_membership> identified by
C<path_id> and C<link_id>. This effectively removes a link from the
path identified by C<path_id>.

=cut
sub remove_link {
    my $args = {
        db             => undef,
        link_id        => undef,
        path_id        => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `link_id` is missing.') if !defined $args->{link_id};
    return (undef, 'Required argument `path_id` is missing.') if !defined $args->{path_id};

    my $q = "
        UPDATE link_path_membership
        SET end_epoch=UNIX_TIMESTAMP(NOW())
        WHERE end_epoch=-1 AND link_id=? AND path_id=?
    ";
    my $res = $args->{db}->execute_query($q, [
        $args->{link_id},
        $args->{path_id}
    ]);
    if (!defined $res) {
        return (undef, $args->{db}->get_error);
    }

    return ($res, undef);
}

=head2 get_links

    my ($links, $err) = OESS::DB::Path::get_links(
        db      => $conn,
        path_id => 1
    );

get_links returns a list of all Links from database C<db> associated
with C<path_id>.

=cut
sub get_links {
    my $args = {
        db => undef,
        path_id => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `path_id` is missing.') if !defined $args->{path_id};

    my $params = [];
    my $values = [];

    if (defined $args->{path_id}) {
        push @$params, 'link_path_membership.path_id=?';
        push @$values, $args->{path_id};
    }

    # push @$params, 'link_instantiation.end_epoch=?';
    # push @$values, -1;

    my $where = (@$params > 0) ? 'WHERE ' . join(' AND ', @$params) : '';

    my $q = "
        SELECT link.link_id, link.name, link.remote_urn, link.status,
               link.metric,
               link_instantiation.interface_a_id, link_instantiation.ip_a,
               link_instantiation.interface_z_id, link_instantiation.ip_z,
               link_path_membership.interface_a_vlan_id as vlan_a_id,
               link_path_membership.interface_z_vlan_id as vlan_z_id,
               interface_a.node_id as node_a_id,
               interface_z.node_id as node_z_id
        FROM link
        JOIN link_instantiation ON link.link_id=link_instantiation.link_id AND link_instantiation.end_epoch=-1
        JOIN link_path_membership ON link.link_id=link_path_membership.link_id AND link_path_membership.end_epoch=-1
        JOIN interface as interface_a ON interface_a.interface_id=link_instantiation.interface_a_id
        JOIN interface as interface_z ON interface_z.interface_id=link_instantiation.interface_z_id
        $where
    ";

    my $links = $args->{db}->execute_query($q, $values);
    if (!defined $links) {
        return (undef, "Couldn't find Links: " . $args->{db}->get_error);
    }

    return ($links, undef);
}

1;
