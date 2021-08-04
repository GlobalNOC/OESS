#!/usr/bin/perl

use strict;
use warnings;

use OESS::User;
use OESS::Interface;
use OESS::DB::User;

package OESS::DB::Workgroup;

=head1 OESS::DB::Workgroup

    use OESS::DB::Workgroup;

=cut

=head2 fetch

    my $wg = OESS::DB::Workgroup::fetch(
        db           => new OESS::DB,
        name         => 'admin',      # Optional
        workgroup_id => 1             # Optional
    );

fetch returns the database record for workgroup C<workgroup_id>.

=cut
sub fetch {
    my $args = {
        db           => undef,
        name         => undef,
        workgroup_id => undef,
        @_
    };

    my $wg;

    if (defined $args->{workgroup_id}) {
        my $q = "select * from workgroup where workgroup_id=? and status='active'";
        $wg = $args->{db}->execute_query($q, [$args->{workgroup_id}]);
    } else {
        my $q = "select * from workgroup where name=? and status='active'";
        $wg = $args->{db}->execute_query($q, [$args->{name}]);
    }
    if (!defined $wg || !defined $wg->[0]) {
        return;
    }

    my @ints;
    my $interfaces = $args->{db}->execute_query(
        "select interface_id from interface where workgroup_id = ?",
        [$wg->[0]->{workgroup_id}]
    );
    if (!defined $interfaces) {
        $interfaces = [];
    }
    $wg->[0]->{interfaces} = $interfaces;

    return $wg->[0];
}

=head2 fetch_all

    my ($workgroups, $error) = OESS::DB::Workgroup::fetch_all(
        db => new OESS::DB
    );

fetch_all returns a list of all workgroups.

=cut
sub fetch_all {
    my $args = {
        db => undef,
        @_
    };

    my $res = $args->{db}->execute_query("select * from workgroup where status='active' order by name", []);
    if (!defined $res) {
        return (undef, $args->{db}->get_error);
    }
    return ($res, undef);
}

=head2 get_users_in_workgroup

=cut
sub get_users_in_workgroup{
    my %params = @_;
    
    my $db = $params{'db'};
    my $workgroup_id = $params{'workgroup_id'};
    
    return (undef, 'Required argument `db` is missing.') if !defined $db;
    return (undef, 'Required argument `workgroup_id` is missing.') if !defined $workgroup_id;

    my $users = $db->execute_query("select user_id, role from user_workgroup_membership where workgroup_id = ?",[$workgroup_id]);
    if(!defined($users)){
        return (undef, "Unable to find any users in workgroup of that workgroup_id");
    }
    
    my @users;
    
    foreach my $u (@$users){
        my $user = OESS::User->new(db => $db, user_id => $u->{'user_id'}, role => $u->{role});
        if(!defined($user)){
            next;
        }
        
        push(@users, $user);
    }
    return (\@users,undef);
}

=head2 create

=cut
sub create {
    my $args = {
        db    => undef,
        model => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `model` is missing.') if !defined $args->{model};
    return (undef, 'Required argument `model->name` is missing.') if !defined $args->{model}->{name};
    if (!defined $args->{model}->{description}) {
        $args->{model}->{description} = "";
    }
    $args->{model}->{type} = $args->{model}->{type} || 'normal';
    my $type_ok = 0;
    my $valid_types = ['normal','admin','demo'];
    foreach my $type (@$valid_types) {
        if ($args->{model}->{type} eq $type) {
            $type_ok = 1;
            last;
        }
    }
    return (undef, "Invalid workgroup type '$args->{model}->{type}' specified.") if !$type_ok;

    my $q = "
        INSERT INTO workgroup (name, description, external_id, type)
        VALUES (?, ?, ?, ?)
    ";
    my $workgroup_id = $args->{db}->execute_query($q, [
        $args->{model}->{name},
        $args->{model}->{description},
        $args->{model}->{external_id},
        $args->{model}->{type}
    ]);
    if (!defined $workgroup_id) {
        return (undef, $args->{db}->get_error);
    }

    return ($workgroup_id, undef);
}

=head2 update

    my ($ok, $err) = OESS::DB::Workgroup::update(
        db => $db,
        model => {
            workgroup_id            => 1,                     # Required
            name                    => 'workgroup',
            description             => '...',
            external_id             => '0000-0000-0000-0000',
            type                    => 'normal',
            max_mac_address_per_end => 10,
            max_circuits            => 50,
            max_circuit_endpoints   => 100,
            status                  => 'active'
        }
    );

update modifies the C<workgroup> database table using C<model>.

=cut
sub update {
    my $args = {
        db  => undef,
        model => {},
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `model` is missing.') if !defined $args->{model};
    return (undef, 'Required argument `model->workgroup_id` is missing.') if !defined $args->{model}->{workgroup_id};

    my $params = [];
    my $values = [];

    if (defined $args->{model}->{name}) {
        push @$params, 'workgroup.name=?';
        push @$values, $args->{model}->{name};
    }

    if (defined $args->{model}->{description}) {
        push @$params, 'workgroup.description=?';
        push @$values, $args->{model}->{description};
    }

    if (defined $args->{model}->{external_id}) {
        push @$params, 'workgroup.external_id=?';
        push @$values, $args->{model}->{external_id};
    }

    if (defined $args->{model}->{type}) {
        push @$params, 'workgroup.type=?';
        push @$values, $args->{model}->{type};
    }

    if (defined $args->{model}->{max_mac_address_per_end}) {
        push @$params, 'workgroup.max_mac_address_per_end=?';
        push @$values, $args->{model}->{max_mac_address_per_end};
    }

    if (defined $args->{model}->{max_circuits}) {
        push @$params, 'workgroup.max_circuits=?';
        push @$values, $args->{model}->{max_circuits};
    }

    if (defined $args->{model}->{max_circuit_endpoints}) {
        push @$params, 'workgroup.max_circuit_endpoints=?';
        push @$values, $args->{model}->{max_circuit_endpoints};
    }

    if (defined $args->{model}->{status}) {
        push @$params, 'workgroup.status=?';
        push @$values, $args->{model}->{status};
    }

    my $fields = join(', ', @$params);
    push @$values, $args->{model}->{workgroup_id};

    my $ok = $args->{db}->execute_query(
        "UPDATE workgroup SET $fields WHERE workgroup_id=?",
        $values
    );
    if (!defined $ok) {
        return (undef, $args->{db}->get_error);
    }

    return ($ok, undef);
}

=head2 add_user

    my ($ok, $err) = OESS::DB::Workgroup::add_user(
        workgroup_id => 100,
        user_id      => 100
    );
    warn $err if (defined $err);

add_user creates a new C<user_workgroup_membership> identified by
C<workgroup_id> and C<user_id>.

=cut
sub add_user {
    my $args = {
        db             => undef,
        user_id        => undef,
        workgroup_id        => undef,
        role           => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `user_id` is missing.') if !defined $args->{user_id};
    return (undef, 'Required argument `workgroup_id` is missing.') if !defined $args->{workgroup_id};
    return (undef, 'Required argument `role` is missing.') if !defined $args->{role};
    my $userExistQuery = " SELECT * from user_workgroup_membership WHERE workgroup_id=? AND user_id=?";
    my $pairExists = $args->{db}->execute_query($userExistQuery, [$args->{workgroup_id}, $args->{user_id}]);
    if (defined $pairExists->[0]){
        return (undef, "User already in workgroup");
    }
    my $query = "
        insert into user_workgroup_membership (
            user_id, workgroup_id, role
        ) VALUES (?, ?, ?)
    ";
    my $res = $args->{db}->execute_query($query, [
        $args->{user_id},
        $args->{workgroup_id},
        $args->{role}
    ]);
    if (!defined $res) {
        return (undef, $args->{db}->get_error);
    }

    return ($res, undef);
}

=head2 edit_user_role
    my ($ok, $err) = OESS::DB::Workgroup::edit_user_role(
        db => $db
        workgroup+id => 100,
        user_id => 10,
        role => read-only
    );
    warn $err if (defined $err);

edit_user_role changes the C<user_workgroup_membership> identified by
C<workgroup_id> and C<user_id>. It takes in a C<role> and modifies
the table to change the C<role> of the specified userin
the specified workgroup identified by C<workgroup_id>

=cut
sub edit_user_role {
    my $args = {
        db           => undef,
        user_id      => undef,
        workgroup_id => undef,
        role         => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `user_id` is missing.') if !defined $args->{user_id};
    return (undef, 'Required argument `workgroup_id` is missing.') if !defined $args->{workgroup_id};
    return (undef, 'Required argument `role` is missing.') if !defined $args->{role};


    my $query = "UPDATE user_workgroup_membership SET role = ? WHERE workgroup_id = ? AND user_id = ?";

    my $result = $args->{db}->execute_query($query, [$args->{role}, $args->{workgroup_id}, $args->{user_id}]);

    if ($result == 0) {
       return (undef, "Unable to edit role - does this user belong to this workgroup?");
    }

    return (1, undef);

}

=head2 remove_user

    my ($ok, $err) = OESS::DB::Workgroup::remove_user(
        workgroup_id => 100,
        user_id => 100
    );
    warn $err if (defined $err);

remove_user decoms the C<user_workgroup_membership> identified by
C<workgroup_id> and C<user_id>. This effectively removes a user from
the workgroup identified by C<workgroup_id>.

=cut
sub remove_user {
    my $args = {
        db           => undef,
        user_id      => undef,
        workgroup_id => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `user_id` is missing.') if !defined $args->{user_id};
    return (undef, 'Required argument `workgroup_id` is missing.') if !defined $args->{workgroup_id};

    my $q = "
        DELETE FROM user_workgroup_membership
        WHERE user_id=? AND workgroup_id=?
    ";
    my $res = $args->{db}->execute_query($q, [
        $args->{user_id},
        $args->{workgroup_id}
    ]);
    if (!defined $res) {
        return (undef, $args->{db}->get_error);
    }

    return ($res, undef);
}

1;
