#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::ACL;

use Data::Dumper;

=head1 OESS::DB::ACL

=cut

=head2 create

    my $id = OESS::DB::ACL::create(
        db => $db,
        model => {
            workgroup_id  => 1,
            interface_id  => 1,
            allow_deny    => 'allow',
            eval_position => 10,
            start         => 100,
            end           => 120,
            notes         => 'group 1-A',
            entity_id     => 1
        }
    );

=cut
sub create {
    my $args = {
        db => undef,
        model => undef,
        @_
    };

    die 'Required argument `db` is missing.' if !defined $args->{db};
    die 'Required argument `model` is missing.' if !defined $args->{model};

    my $error = undef;
    my $id = $args->{db}->execute_query(
        "insert into interface_acl (workgroup_id, interface_id, allow_deny, eval_position, vlan_start, vlan_end, notes, entity_id) VALUES (?,?,?,?,?,?,?,?)",
        [
            $args->{model}->{workgroup_id},
            $args->{model}->{interface_id},
            $args->{model}->{allow_deny},
            $args->{model}->{eval_position},
            $args->{model}->{start},
            $args->{model}->{end},
            $args->{model}->{notes},
            $args->{model}->{entity_id}
        ]
    );
    if (!defined $id) {
        $error = $args->{db}->get_error();
    }

    return ($id, $error);
}

=head2 fetch

    my $acl = OESS::DB::ACL::fetch(db => $conn, interface_acl_id => 1);

fetch returns ACL C<id> from the database.

=cut
sub fetch {
    my $args = {
        db => undef,
        interface_acl_id => undef,
        @_
    };

    die 'Required argument `db` is missing.' if !defined $args->{db};
    die 'Required argument `interface_acl_id` is missing.' if !defined $args->{interface_acl_id};

    my $acl = $args->{db}->execute_query(
        "select interface_acl_id, workgroup_id, interface_id, allow_deny, eval_position, vlan_start as start, vlan_end as end, notes, entity_id
         from interface_acl where interface_acl_id=?",
        [$args->{interface_acl_id}]
    );
    return undef if (!defined $acl || !defined $acl->[0]);

    return $acl->[0];
}

=head2 fetch_all

    my $acl = OESS::DB::ACL::fetch_all(
        db           => $conn,
        entity_id    => 1,     # Optional
        interface_id => 1,     # Optional
        workgroup_id => 1      # Optional
    );

fetch_all returns a list of all ACLs from the database filtered by
C<entity_id>, C<interface_id>, and C<workgroup_id>.

=cut
sub fetch_all {
    my $args = {
        db => undef,
        entity_id => undef,
        interface_id => undef,
        workgroup_id => undef,
        @_
    };

    die 'Required argument `db` is missing.' if !defined $args->{db};

    my $params = [];
    my $values = [];

    if (defined $args->{entity_id}) {
        push @$params, 'entity_id=?';
        push @$values, $args->{entity_id};
    }
    if (defined $args->{interface_id}) {
        push @$params, 'interface_id=?';
        push @$values, $args->{interface_id};
    }
    if (defined $args->{workgroup_id}) {
        push @$params, 'workgroup_id=?';
        push @$values, $args->{workgroup_id};
    }

    my $where = (@$params > 0) ? 'where ' . join(' and ', @$params) : '';

    my $acls = $args->{db}->execute_query(
        "select interface_acl_id, workgroup_id, interface_id, allow_deny, eval_position, vlan_start as start, vlan_end as end, notes, entity_id
         from interface_acl $where order by eval_position asc",
        $values
    );
    return [] if (!defined $acls);

    return $acls;
}

=head2 update

    my $id = OESS::DB::ACL::update(
        db => $db,
        acl => {
            interface_acl_id => 1,
            workgroup_id     => 1,           # Optional
            interface_id     => 1,           # Optional
            allow_deny       => 'allow',     # Optional
            eval_position    => 10,          # Optional
            start            => 100,         # Optional
            end              => 120,         # Optional
            notes            => 'group 1-A', # Optional
            entity_id        => 1            # Optional
        }
    );

=cut
sub update {
    my $args = {
        db  => undef,
        acl => {},
        @_
    };

    return if !defined $args->{acl}->{interface_acl_id};

    my $params = [];
    my $values = [];

    if (defined $args->{acl}->{workgroup_id}) {
        push @$params, 'workgroup_id=?';
        push @$values, $args->{acl}->{workgroup_id};
    }
    if (defined $args->{acl}->{interface_id}) {
        push @$params, 'interface_id=?';
        push @$values, $args->{acl}->{interface_id};
    }
    if (defined $args->{acl}->{allow_deny}) {
        push @$params, 'allow_deny=?';
        push @$values, $args->{acl}->{allow_deny};
    }
    if (defined $args->{acl}->{eval_position}) {
        push @$params, 'eval_position=?';
        push @$values, $args->{acl}->{eval_position};
    }
    if (defined $args->{acl}->{start}) {
        push @$params, 'vlan_start=?';
        push @$values, $args->{acl}->{start};
    }
    if (defined $args->{acl}->{end}) {
        push @$params, 'vlan_end=?';
        push @$values, $args->{acl}->{end};
    }
    if (defined $args->{acl}->{notes}) {
        push @$params, 'notes=?';
        push @$values, $args->{acl}->{notes};
    }
    if (defined $args->{acl}->{entity_id}) {
        push @$params, 'entity_id=?';
        push @$values, $args->{acl}->{entity_id};
    }

    my $fields = join(', ', @$params);
    push @$values, $args->{acl}->{interface_acl_id};

    return $args->{db}->execute_query(
        "UPDATE interface_acl SET $fields WHERE interface_acl_id=?",
        $values
    );
}

return 1;
