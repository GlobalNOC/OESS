use strict;
use warnings;

package OESS::DB::Link;

use Data::Dumper;

=head1 OESS::DB::Link

=cut

=head2 create

    my $id = OESS::DB::Link::create(
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
               link_instantiation.interface_a_id, link_instantiation.ip_a,
               link_instantiation.interface_z_id, link_instantiation.ip_z
        FROM link
        JOIN link_instantiation ON link.link_id=link_instantiation.link_id
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

=head2 fetch_all

    my $acl = OESS::DB::Link::fetch_all(
        db           => $conn,
        link_id      => 1,             # Optional
        path_id      => 1,             # Optional
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
        db => undef,
        path_id => undef,
        link_id => undef,
        name => undef,
        remote_urn => undef,
        status => undef,
        ip => undef,
        interface_id => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};

    my $params = [];
    my $values = [];

    if (defined $args->{link_id}) {
        push @$params, 'link.link_id=?';
        push @$values, $args->{link_id};
    }
    if (defined $args->{path_id}) {
        push @$params, 'link_path_membership.path_id=?';
        push @$values, $args->{path_id};
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

    push @$params, 'link_instantiation.end_epoch=?';
    push @$values, -1;

    my $where = (@$params > 0) ? 'WHERE ' . join(' AND ', @$params) : '';

    my $q = "
        SELECT link.link_id, link.name, link.remote_urn, link.status,
               link.metric,
               link_instantiation.interface_a_id, link_instantiation.ip_a,
               link_instantiation.interface_z_id, link_instantiation.ip_z
        FROM link
        JOIN link_instantiation ON link.link_id=link_instantiation.link_id
        JOIN link_path_membership ON link.link_id=link_path_membership.link_id
        $where
    ";

    my $links = $args->{db}->execute_query($q, $values);
    if (!defined $links) {
        return (undef, "Couldn't find Links: " . $args->{db}->get_error);
    }

    return $links;
}

1;
