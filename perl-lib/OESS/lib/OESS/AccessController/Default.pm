package OESS::AccessController::Default;

use strict;
use warnings;

use Data::Dumper;

use OESS::DB;
use OESS::DB::ACL;
use OESS::DB::Interface;
use OESS::DB::User;
use OESS::User;
use OESS::Workgroup;

=head2 new

=cut
sub new {
    my $class = shift;
    my $args  = {
        db => undef,
        @_
    };

    return bless $args, $class;
}

=head2 create_user

=cut
sub create_user {
    my $self = shift;
    my $args = {
        email      => undef,
        first_name => undef,
        last_name  => undef,
        usernames  => undef,
        @_
    };

    my $user = new OESS::User(
        db    => $self->{db},
        model => {
            email      => $args->{email},
            first_name => $args->{first_name},
            last_name  => $args->{last_name},
            username   => $args->{username}
        }
    );
    return $user->create;
}

=head2 delete_user

=cut
sub delete_user {
    my $self = shift;
    my $args = {
        user_id => undef,
        @_
    };

    my (undef, $err) = OESS::DB::User::delete_user(
        db => $self->{db},
        user_id => $args->{user_id}
    );
    return $err;
}

=head2 edit_user

    my $err = $access_controller->edit_user(
        ...
    );

=cut
sub edit_user {
    my $self = shift;
    my $args = {
        email       => undef,
        first_name  => undef,
        last_name   => undef,
        user_id     => undef,
        usernames   => undef,
        @_
    };

    $self->{db}->start_transaction;

    my $user = new OESS::User(
        db      => $self->{db},
        user_id => $args->{user_id}
    );
    $user->first_name($args->{first_name});
    $user->last_name($args->{last_name});
    $user->email($args->{email});

    # Handle change in usernames
    my $username_index = {};
    foreach my $username (@{$user->usernames}) {
        $username_index->{$username} = 1;
    }

    foreach my $username (@{$args->{usernames}}) {
        if (defined $username_index->{$username}) {
            delete $username_index->{$username};
        }
        $user->add_username($username);
    }

    foreach my $username (keys %{$username_index}) {
        $user->remove_username($username);
    }

    my $err = $user->update;
    if (defined $err) {
        $self->{db}->rollback;
        return ($user, $err);
    }

    my $ok = $self->{db}->commit;
    if (!$ok) {
        return ($user, "Couldn't update user: " . $self->{db}->get_error);
    }
    return ($user, undef);
}

=head2 get_user

=cut
sub get_user {
    my $self = shift;
    my $args = {
        user_id  => undef,
        username => undef,
        @_
    };

    if (!defined $args->{user_id} && !defined $args->{username}) {
        return (undef, "Required argument `user_id` or `username`.");
    }

    my $result = new OESS::User(
        db       => $self->{db},
        user_id  => $args->{user_id},
        username => $args->{username}
    );
    if (!defined $result) {
        return (undef, "Couldn't find user $args->{username}.");
    }
    $result->load_workgroups;

    return ($result, undef);
}

=head2 get_users

    my ($users, $err) = $ac->get_users();

=cut
sub get_users {
    my $self = shift;
    my $args = {
        @_
    };

    my ($users, $err) = OESS::DB::User::fetch_all_v2(
        db => $self->{db}
    );
    if (defined $err) {
        return (undef, $err);
    }

    my $result = [];
    foreach my $user_model (@$users) {
        my $user = new OESS::User(
            db    => $self->{db},
            model => $user_model
        );
        push @$result, $user;
    }

    return ($result, undef);
}

=head2 create_workgroup

=cut
sub create_workgroup {
    my $self = shift;
    my $args = {
        description => undef,
        external_id => undef,
        name        => undef,
        type        => undef,
        @_
    };

    my $wg = new OESS::Workgroup(
        db => $self->{db},
        model => {
            description => $args->{description},
            external_id => $args->{external_id},
            name        => $args->{name},
            type        => $args->{type}
        }
    );
    return $wg->create;
}

=head2 delete_workgroup

    my $err = $access_controller->delete_workgroup(
        workgroup_id => 123
    );

=cut
sub delete_workgroup {
    my $self = shift;
    my $args = {
        workgroup_id => undef,
        @_
    };

    $self->{db}->start_transaction;

    my $wg = new OESS::Workgroup(
        db => $self->{db},
        workgroup_id => $args->{workgroup_id}
    );
    if (!defined $wg) {
        $self->{db}->rollback;
        return "Couldn't find workgroup $args->{workgroup_id}.";
    }

    $wg->status('decom');
    my $err = $wg->update;
    if (defined $err) {
        $self->{db}->rollback;
        return $err;
    }

    my $interface_ids = OESS::DB::Interface::get_interfaces(
        db => $self->{db},
        workgroup_id => $args->{workgroup_id}
    );
    foreach my $id (@$interface_ids) {
        my ($count, $acl_error) = OESS::DB::ACL::remove_all(db => $self->{db}, interface_id => $id);
        if (defined $acl_error) {
            warn "$acl_error";
        }
    }

    $self->{db}->commit;
    return;
}

=head2 edit_workgroup

=cut
sub edit_workgroup {
    my $self = shift;
    my $args = {
        description  => undef,
        external_id  => undef,
        name         => undef,
        type         => undef,
        workgroup_id => undef,
        @_
    };

    my $wg = new OESS::Workgroup(
        db => $self->{db},
        workgroup_id => $args->{workgroup_id}
    );
    $wg->description($args->{description});
    $wg->external_id($args->{external_id});
    $wg->name($args->{name});
    $wg->type($args->{type});

    return $wg->update;
}

=head2 get_workgroup

=cut
sub get_workgroup {
    my $self = shift;
    my $args = {
        workgroup_id => undef,
        @_
    };

    my $wg = new OESS::Workgroup(db => $self->{db}, workgroup_id => $args->{workgroup_id});
    return (undef, "Couldn't find workgroup $args->{workgroup_id}.") if !defined $wg;

    return ($wg, undef);
}

=head2 get_workgroups

=cut
sub get_workgroups {
    my $self = shift;
    my $args = {
        @_
    };
    return;
}

=head2 get_workgroup_users

=cut
sub get_workgroup_users {
    my $self = shift;
    my $args = {
        workgroup_id => undef,
        @_
    };

    my $wg = new OESS::Workgroup(db => $self->{db}, workgroup_id => $args->{workgroup_id});
    return (undef, "Couldn't find workgroup $args->{workgroup_id}.") if !defined $wg;

    my $err = $wg->load_users;
    return ($wg->users, $err);
}

=head2 add_workgroup_user

=cut
sub add_workgroup_user {
    my $self = shift;
    my $args = {
        user_id      => undef,
        workgroup_id => undef,
        role         => undef,
        @_
    };

    if (!defined $args->{user_id} || !defined $args->{workgroup_id} || !defined $args->{role}) {
        return "Required argument `user_id` `workgroup_id` or `role` missing.";
    }

    $self->{db}->start_transaction;

    my $wg = new OESS::Workgroup(db => $self->{db}, workgroup_id => $args->{workgroup_id});
    return "Couldn't find workgroup $args->{workgroup_id}." if !defined $wg;

    my $err = $wg->load_users;
    return $err if defined $err;

    my ($user, $user_err) = $self->get_user(user_id => $args->{user_id});
    if (defined $user_err) {
        return "Couldn't find user $args->{user_id}." if !defined $user;
    }
    $user->role($args->{role});

    $err = $wg->add_user($user);
    return $err if defined $err;

    $err = $wg->update;
    return $err if defined $err;

    my $ok = $self->{db}->commit;
    return "Couldn't add workgroup user. Unknown error occurred." if !$ok;
    return;
}

=head2 modify_workgroup_user

=cut
sub modify_workgroup_user {
    my $self = shift;
    my $args = {
        user_id      => undef,
        workgroup_id => undef,
        role         => undef,
        @_
    };

    if (!defined $args->{user_id} && !defined $args->{workgroup_id}) {
        return "Required argument `user_id` or `workgroup_id` missing.";
    }

    $self->{db}->start_transaction;

    my $wg = new OESS::Workgroup(db => $self->{db}, workgroup_id => $args->{workgroup_id});
    return "Couldn't find workgroup $args->{workgroup_id}." if !defined $wg;

    my $err = $wg->load_users;
    return $err if defined $err;

    $err = $wg->modify_user($args->{user_id}, $args->{role});
    return $err if defined $err;

    my $ok = $self->{db}->commit;
    return "Couldn't modify workgroup user. Unknown error occurred." if !$ok;
    return;
}

=head2 remove_workgroup_user

=cut
sub remove_workgroup_user {
    my $self = shift;
    my $args = {
        user_id      => undef,
        workgroup_id => undef,
        @_
    };

    if (!defined $args->{user_id} && !defined $args->{workgroup_id}) {
        return "Required argument `user_id` or `workgroup_id` missing.";
    }

    $self->{db}->start_transaction;

    my $wg = new OESS::Workgroup(db => $self->{db}, workgroup_id => $args->{workgroup_id});
    return "Couldn't find workgroup $args->{workgroup_id}." if !defined $wg;

    my $err = $wg->load_users;
    return $err if defined $err;

    $err = $wg->remove_user($args->{user_id});
    return $err if defined $err;

    $err = $wg->update;
    return $err if defined $err;

    my $ok = $self->{db}->commit;
    return "Couldn't remove workgroup user. Unknown error occurred." if !$ok;
    return;
}

return 1;
