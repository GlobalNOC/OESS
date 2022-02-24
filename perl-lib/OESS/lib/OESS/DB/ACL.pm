#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::ACL;

use Log::Log4perl;
use OESS::AccessController::Default;

my $logger = Log::Log4perl->get_logger("OESS.ACL");

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

    if (defined $args->{model}->{eval_position}) {
        if ( _has_used_eval_position(db => $args->{db}, interface_id => $args->{model}->{interface_id}, eval_position => $args->{model}->{eval_position})) {
            return (undef, $args->{db}->get_error());
        }
    } else {
        $args->{model}->{eval_position} = _get_next_eval_position( db => $args->{db}, interface_id => $args->{model}->{interface_id} );
    }

    my $error = undef;
    my $id = $args->{db}->execute_query(
        "insert into interface_acl (workgroup_id, interface_id, allow_deny, eval_position, vlan_start, vlan_end, notes, entity_id) VALUES (?,?,?,?,?,?,?,?)",
        [
            ($args->{model}->{workgroup_id} == -1) ? undef : $args->{model}->{workgroup_id},
            $args->{model}->{interface_id},
            $args->{model}->{allow_deny},
            $args->{model}->{eval_position},
            $args->{model}->{start},
            $args->{model}->{end},
            $args->{model}->{notes},
            ($args->{model}->{entity_id} == -1) ? undef : $args->{model}->{entity_id}
        ]
    );
    if (!defined $id) {
        $error = $args->{db}->get_error();
    }
    my $user_id = $args->{model}->{user_id} ? $args->{model}->{user_id} : '-1';
    my $workgroup_id = $args->{model}->{workgroup_id} ? $args->{model}->{workgroup_id} : '-1';
    my $interface_id = $args->{model}->{interface_id} ? $args->{model}->{interface_id} : '-1';
    my $query = "insert into acl_history (acl_history_id, date, user_id, workgroup_id, interface_id, interface_acl_id, event)
                 values (null, unix_timestamp(now()), ?, ?, ?, ?, 'ACL Created')";
    my $acl_history = $args->{db}->execute_query($query,[$user_id, $workgroup_id, $interface_id, $id]);

    return ($id, $error);
}

=head2 _has_used_eval_position

Returns true if the acl's eval position is already used

=cut
sub _has_used_eval_position {
    my %args = @_;

    if (!defined $args{'interface_id'} || !defined $args{'eval_position'}) {
        $args{'db'}->set_error("Must pass interface id and eval_position");
        return;
    }
    my $result = $args{'db'}->execute_query(
        "select 1 from interface_acl where interface_id = ? and eval_position = ?",
        [$args{'interface_id'},$args{'eval_position'}]
    );
    if(!defined($result)) {
        $args{'db'}->set_error("Could not query interface acl eval positions");
        return;
    }

    if (@$result > 0) {
        $args{'db'}->set_error("There is already an acl at eval position $args{'eval_position'}");
        return 1;
    } else {
        return 0;
    }
}

=head2 _get_next_eval_position

Returns the max eval position plus ten

=cut
sub _get_next_eval_position {
    my %args = @_;

    if (!defined $args{'interface_id'}) {
        $args{'db'}->set_error("Must pass in interface_id");
        return;
    }

    my $result = $args{'db'}->execute_query(
        "SELECT max(interface_acl.eval_position) as max_eval_position from interface_acl where interface_id = ?",
        [$args{'interface_id'}]
    );
    if (!defined $result) {
        $args{'db'}->set_error("Could not query max interface acl eval position");
        return;
    }

    if (@$result <= 0) {
        return 10;
    } else {
        return ($result->[0]{'max_eval_position'} + 10);
    }
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
        "select interface_acl_id, interface_acl.workgroup_id, workgroup.name as workgroup_name, interface_id, allow_deny, eval_position, interface_acl.vlan_start as start, vlan_end as end, notes, interface_acl.entity_id, entity.name as entity_name
         from interface_acl LEFT JOIN entity ON interface_acl.entity_id = entity.entity_id
         LEFT JOIN workgroup ON interface_acl.workgroup_id = workgroup.workgroup_id
         where interface_acl_id=?",
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
        push @$params, 'interface_acl.entity_id=?';
        push @$values, $args->{entity_id};
    }
    if (defined $args->{interface_id}) {
        push @$params, 'interface_id=?';
        push @$values, $args->{interface_id};
    }
    if (defined $args->{workgroup_id}) {
        push @$params, 'interface_acl.workgroup_id=?';
        push @$values, $args->{workgroup_id};
    }

    my $where = (@$params > 0) ? 'where ' . join(' and ', @$params) : '';

    my $acls = $args->{db}->execute_query(
        "select interface_acl_id, interface_acl.workgroup_id, workgroup.name as workgroup_name, interface_id, allow_deny, eval_position, interface_acl.vlan_start as start, vlan_end as end, notes, interface_acl.entity_id, entity.name as entity_name
         from interface_acl LEFT JOIN entity ON entity.entity_id=interface_acl.entity_id 
         LEFT JOIN workgroup ON interface_acl.workgroup_id = workgroup.workgroup_id
         $where order by eval_position asc",
        $values
    );
    return undef if (!defined $acls);

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
        if ($args->{acl}->{workgroup_id} != -1) {
            push @$values, $args->{acl}->{workgroup_id};
        } else {
            push @$values, undef;
        }
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
        if ($args->{acl}->{entity_id} != -1) {
            push @$values, $args->{acl}->{entity_id};
        } else {
            push @$values, undef;
        }
    }
    my $fields = join(', ', @$params);
    
    push @$values, $args->{acl}->{interface_acl_id};

    my $ac = new OESS::AccessController::Default(db => $args->{db});
    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    my $workgroup_id = $args->{acl}->{workgroup_id} ? $args->{acl}->{workgroup_id} : '-1';
    my $interface_id = $args->{acl}->{interface_id} ? $args->{acl}->{interface_id} : '-1';
    my $query = "insert into acl_history (acl_history_id, date, user_id, workgroup_id, interface_id, interface_acl_id, event)
                 values (null, unix_timestamp(now()), ?, ?, ?, ?, 'ACL Updated')";
    my $acl_history = $args->{db}->execute_query($query,[$user->user_id, $workgroup_id, $interface_id, $args->{acl}->{interface_acl_id}]);

    return $args->{db}->execute_query(
        "UPDATE interface_acl SET $fields WHERE interface_acl_id=?",
        $values
    );
}

=head2 remove

    my ($output, $error) = OESS::DB::ACL::remove(
        db => $db,
        interface_acl_id => 1
    );

=cut

sub remove {
    my $args = {
        db => undef,
        interface_acl_id => undef,
        @_
    };
    return (0, "db is a required parameter") if !defined $args->{db};
    return (0, "interface_acl_id is a required parameter") if !defined $args->{interface_acl_id};

    my $query = "DELETE FROM interface_acl WHERE interface_acl_id = ?";
    my $count = $args->{db}->execute_query($query,[$args->{interface_acl_id}]);
    if (!defined $count) {
        return(0, "Error removing acl");
    }
    if( $count == 0){
        return(0, "Error interface_acl_id did not exist");
    }
    return(1,undef);
}

=head2 remove_all

    my ($output, $error) = OESS::DB::ACL::remove_all(
        db => $db,
        interface_id => 1
    );

Deletes all ACLs on a given interface used during the workgroup decoming process
=cut

sub remove_all {
    my $args = {
        db => undef,
        interface_id => undef,
        @_
    };

    return (0,"db is a required parameter") if !defined $args->{db};
    return (0,"interface_id is a required parameter") if !defined $args->{interface_id};

    my $query = "DELETE FROM interface_acl WHERE interface_id = ?";
    my $count = $args->{db}->execute_query($query,[$args->{interface_id}]);

    if (!defined $count) {
        return (-1, "Error removing acls");
    }
    return ($count, undef);
}

=head2 get_acl_history
=cut

sub get_acl_history {
    my $args = {
        db => undef,
        interface_acl_id => undef,
        interface_id => undef,
        workgroup_id => undef,
        @_
    };

    my $query = "select * from acl_history where interface_id = ? and interface_acl_id = ? and workgroup_id = ?";
    return $args->{db}->execute_query($query, [$args->{interface_id}, $args->{interface_acl_id}, $args->{workgroup_id}]);
}

return 1;
