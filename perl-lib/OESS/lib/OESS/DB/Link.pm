use strict;
use warnings;

package OESS::DB::Link;

use Data::Dumper;

=head1 OESS::DB::Link

    use OESS::DB::Link;

=cut

=head2 create

    my ($id, $err) = OESS::DB::Link::create(
        db => $db,
        model => {
            name           => 'node-a-to-node-b',
            remote_urn     => '',
            status         => 'up',
            metric         => 1,
            interface_a_id => 1,
            ip_a           => '192.168.1.2',
            interface_z_id => 2,
            ip_z           => '192.168.1.3'
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
        INSERT INTO link (name, remote_urn, status, metric)
        VALUES (?,?,?,?)
    ";

    my $q2 = "
        INSERT INTO link_instantiation (
            link_id, openflow, mpls, interface_a_id, ip_a,
            interface_z_id, ip_z, start_epoch, end_epoch
        )
        VALUES (?,?,?,?,?,?,?,UNIX_TIMESTAMP(NOW()),-1)
    ";

    my $q3 = "
        UPDATE interface set role='trunk' WHERE interface_id=? or interface_id=?
    ";

    my $link_id = $args->{db}->execute_query($q1, [
        $args->{model}->{name},
        $args->{model}->{remote_urn},
        $args->{model}->{status},
        $args->{model}->{metric}
    ]);
    if (!defined $link_id) {
        return (undef, $args->{db}->get_error);
    }

    my $link_instantiation_id = $args->{db}->execute_query($q2, [
        $link_id,
        0,
        1,
        $args->{model}->{interface_a_id},
        $args->{model}->{ip_a},
        $args->{model}->{interface_z_id},
        $args->{model}->{ip_z}
    ]);
    if (!defined $link_instantiation_id) {
        return (undef, $args->{db}->get_error);
    }

    my $ok = $args->{db}->execute_query($q3, [
        $args->{model}->{interface_a_id},
        $args->{model}->{interface_z_id}
    ]);
    if (!defined $ok) {
        return (undef, $args->{db}->get_error);
    }

    return ($link_id, undef);
}

=head2 fetch

    my $link = OESS::DB::Link::fetch(db => $conn, link_id => 1);

fetch returns Link C<link_id> from database C<db>.

=cut
sub fetch {
    my $args = {
        db => undef,
        link_id => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `link_id` is missing.') if !defined $args->{link_id};

    my $q = "
        SELECT link.link_id, link.name, link.remote_urn, link.status,
               link.metric,
               link_instantiation.link_state,
               link_instantiation.interface_a_id, link_instantiation.ip_a,
               link_instantiation.interface_z_id, link_instantiation.ip_z,
               interface_a.node_id as node_a_id,
               interface_z.node_id as node_z_id,
               node_a.loopback_address as node_a_loopback, node_z.loopback_address as node_z_loopback,
               node_a.controller as node_a_controller, node_z.controller as node_z_controller
        FROM link
        JOIN link_instantiation ON link.link_id=link_instantiation.link_id AND link_instantiation.end_epoch=-1
        JOIN interface as interface_a ON interface_a.interface_id=link_instantiation.interface_a_id
        JOIN interface as interface_z ON interface_z.interface_id=link_instantiation.interface_z_id
        JOIN node_instantiation as node_a ON node_a.node_id=interface_a.node_id AND node_a.end_epoch=-1
        JOIN node_instantiation as node_z ON node_z.node_id=interface_z.node_id AND node_z.end_epoch=-1
        WHERE link.link_id=? AND link_instantiation.end_epoch=-1
    ";
    my $link = $args->{db}->execute_query($q, [
        $args->{link_id}
    ]);
    if (!defined $link) {
        return (undef, "Couldn't find Link $args->{link_id}: " . $args->{db}->get_error);
    }
    if (!defined $link->[0]) {
        return (undef, "Couldn't find Link $args->{link_id}.");
    }

    return ($link->[0], undef);
}

=head2 fetch_history

    my $link = OESS::DB::Link::fetch(db => $conn, link_id => 1);

fetch_history returns every instantiation of Link C<link_id> from
database C<db>.

=cut
sub fetch_history {
    my $args = {
        db => undef,
        link_id => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `link_id` is missing.') if !defined $args->{link_id};

    my $q = "
        SELECT link.link_id, link.name, link.remote_urn, link.status,
               link.metric,
               link_instantiation.link_state,
               link_instantiation.interface_a_id, link_instantiation.ip_a,
               link_instantiation.interface_z_id, link_instantiation.ip_z,
               interface_a.node_id as node_a_id,
               interface_z.node_id as node_z_id,
               node_a.loopback_address as node_a_loopback, node_z.loopback_address as node_z_loopback
        FROM link
        JOIN link_instantiation ON link.link_id=link_instantiation.link_id
        JOIN interface as interface_a ON interface_a.interface_id=link_instantiation.interface_a_id
        JOIN interface as interface_z ON interface_z.interface_id=link_instantiation.interface_z_id
        JOIN node_instantiation as node_a ON node_a.node_id=interface_a.node_id AND node_a.end_epoch=-1
        JOIN node_instantiation as node_z ON node_z.node_id=interface_z.node_id AND node_z.end_epoch=-1
        WHERE link.link_id=?
    ";
    my $links = $args->{db}->execute_query($q, [
        $args->{link_id}
    ]);
    if (!defined $links) {
        return (undef, "Couldn't find history of Link $args->{link_id}: " . $args->{db}->get_error);
    }

    return ($links, undef);
}

=head2 fetch_all

    my ($links, $err) = OESS::DB::Link::fetch_all(
        db           => $conn,
        link_id      => 1,             # Optional
        name         => 'a-to-b',      # Optional
        remote_urn   => '',            # Optional
        status       => 'up',          # Optional
        ip           => '192.168.1.2', # Optional
        interface_id => 2,             # Optional
    );

fetch_all returns a list of all Links from database C<db> filtered by
C<link_id>, C<name>, C<remote_urn>, C<ip>, C<interface_id>, and
C<status>.

=cut
sub fetch_all {
    my $args = {
        db           => undef,
        path_id      => undef,
        link_id      => undef,
        name         => undef,
        remote_urn   => undef,
        status       => undef,
        ip           => undef,
        interface_id => undef,
        controller   => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};

    my $params = [];
    my $values = [];

    if (defined $args->{link_id}) {
        push @$params, 'link.link_id=?';
        push @$values, $args->{link_id};
    }
    if (defined $args->{name}) {
        push @$params, 'link.name=?';
        push @$values, $args->{name};
    }
    if (defined $args->{remote_urn}) {
        push @$params, 'link.remote_urn=?';
        push @$values, $args->{remote_urn};
    }
    if (defined $args->{status}) {
        push @$params, 'link.status=?';
        push @$values, $args->{status};
    }
    if (defined $args->{ip}) {
        push @$params, '(link_instantiation.ip_a=? OR link_instantiation.ip_z=?';
        push @$values, $args->{ip};
        push @$values, $args->{ip};
    }
    if (defined $args->{interface_id}) {
        push @$params, '(link_instantiation.interface_a_id=? OR link_instantiation.interface_z_id=?)';
        push @$values, $args->{interface_id};
        push @$values, $args->{interface_id};
    }

    if (defined $args->{controller}) {
        push @$params, '(node_a.controller=? AND node_z.controller=?)';
        push @$values, $args->{controller};
        push @$values, $args->{controller};
    }

    push @$params, 'link_instantiation.end_epoch=?';
    push @$values, -1;

    push @$params, 'link_instantiation.link_state!=?';
    push @$values, 'decom';

    my $where = (@$params > 0) ? 'WHERE ' . join(' AND ', @$params) : '';

    my $q = "
        SELECT link.link_id, link.name, link.remote_urn, link.status,
               link.metric,
               link_instantiation.link_state,
               link_instantiation.interface_a_id, link_instantiation.ip_a,
               link_instantiation.interface_z_id, link_instantiation.ip_z,
               interface_a.node_id as node_a_id,
               interface_z.node_id as node_z_id,
               node_a.loopback_address as node_a_loopback, node_z.loopback_address as node_z_loopback,
               node_a.controller as node_a_controller, node_z.controller as node_z_controller
        FROM link
        JOIN link_instantiation ON link.link_id=link_instantiation.link_id AND link_instantiation.end_epoch=-1
        JOIN interface as interface_a ON interface_a.interface_id=link_instantiation.interface_a_id
        JOIN interface as interface_z ON interface_z.interface_id=link_instantiation.interface_z_id
        JOIN node_instantiation as node_a ON node_a.node_id=interface_a.node_id AND node_a.end_epoch=-1
        JOIN node_instantiation as node_z ON node_z.node_id=interface_z.node_id AND node_z.end_epoch=-1
        $where
    ";

    my $links = $args->{db}->execute_query($q, $values);
    if (!defined $links) {
        return (undef, "Couldn't find Links: " . $args->{db}->get_error);
    }

    return ($links, undef);
}

=head2 update

    my ($id, $error) = OESS::DB::Link::update(
        db => $db,
        link => {
            link_id        => 1,
            link_state     => 'active',
            interface_a_id => 100,
            ip_a           => undef,
            interface_z_id => 21,
            ip_z           => undef,
            name           => 'Link',   # Optional
            status         => 'up',     # Optional
            remote_urn     => undef,    # Optional
            metric         => 553       # Optional
        }
    );

=cut
sub update {
    my $args = {
        db  => undef,
        link => {},
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `link->link_id` is missing.') if !defined $args->{link}->{link_id};
    return (undef, 'Required argument `link->link_state` is missing.') if !defined $args->{link}->{link_state};
    return (undef, 'Required argument `link->interface_a_id` is missing.') if !defined $args->{link}->{interface_a_id};
    return (undef, 'Required argument `link->ip_a` is missing.') if !exists $args->{link}->{ip_a};
    return (undef, 'Required argument `link->interface_z_id` is missing.') if !defined $args->{link}->{interface_z_id};
    return (undef, 'Required argument `link->ip_z` is missing.') if !exists $args->{link}->{ip_z};

    my $params = [];
    my $values = [];

    if (defined $args->{link}->{name}) {
        push @$params, 'name=?';
        push @$values, $args->{link}->{name};
    }
    if (defined $args->{link}->{status}) {
        push @$params, 'status=?';
        push @$values, $args->{link}->{status};
    }
    if (defined $args->{link}->{remote_urn}) {
        push @$params, 'remote_urn=?';
        push @$values, $args->{link}->{remote_urn};
    }
    if (defined $args->{link}->{metric}) {
        push @$params, 'metric=?';
        push @$values, $args->{link}->{metric};
    }

    my $fields = join(', ', @$params);
    push @$values, $args->{link}->{link_id};

    if (@$values > 1) {
        my $ok = $args->{db}->execute_query("UPDATE link SET $fields WHERE link_id=?", $values);
        if (!defined $ok) {
            return (undef, $args->{db}->get_error);
        }
    }

    my $inst_ok = $args->{db}->execute_query(
        "UPDATE link_instantiation SET end_epoch=UNIX_TIMESTAMP(NOW()) WHERE link_id=? and end_epoch=-1",
        [$args->{link}->{link_id}]
    );
    if (!defined $inst_ok) {
        return (undef, $args->{db}->get_error);
    }

    my $q2 = "
        INSERT INTO link_instantiation (
            link_id, openflow, mpls, link_state, interface_a_id, ip_a,
            interface_z_id, ip_z, start_epoch, end_epoch
        )
        VALUES (?,?,?,?,?,?,?,?,UNIX_TIMESTAMP(NOW()),-1)
    ";

    my $link_instantiation_id = $args->{db}->execute_query($q2, [
        $args->{link}->{link_id},
        0,
        1,
        $args->{link}->{link_state},
        $args->{link}->{interface_a_id},
        $args->{link}->{ip_a},
        $args->{link}->{interface_z_id},
        $args->{link}->{ip_z}
    ]);
    if (!defined $link_instantiation_id) {
        return (undef, $args->{db}->get_error);
    }

    # Set role of interfaces to 'unknown' whenever a link is
    # decom'd. This allows the link's interfaces to be used for other
    # purposes after removal.
    if ($args->{link}->{link_state} eq 'decom') {
        my $q3 = "
            UPDATE interface set role='unknown' WHERE interface_id=? or interface_id=?
        ";

        my $ok = $args->{db}->execute_query($q3, [
            $args->{model}->{interface_a_id},
            $args->{model}->{interface_z_id}
        ]);
        if (!defined $ok) {
            return (undef, $args->{db}->get_error);
        }
    }

    return ($link_instantiation_id, undef);
}

1;
