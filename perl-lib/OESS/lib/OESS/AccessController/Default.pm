package OESS::AccessController::Default;

use strict;
use warnings;

use OESS::DB;
use OESS::DB::ACL;
use OESS::DB::Interface;
use OESS::DB::User;
use OESS::User;

sub new {
    my $class = shift;
    my $args  = {
        db => undef,
        @_
    };

    return bless $args, $class;
}

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

sub edit_user {
    my $self = shift;
    my $args = {
        email      => undef,
        first_name => undef,
        last_name  => undef,
        user_id    => undef,
        username   => undef
    };

    return 1;
}

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
    return ($result, undef);
}

sub get_users {
    my $self = shift;
    my $args = {
        @_
    };
    return;
}
sub get_user_workgroups {
    my $self = shift;
    my $args = {
        @_
    };
    return;
}

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
    return undef;
}

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

sub get_workgroups {
    my $self = shift;
    my $args = {
        @_
    };
    return;
}

sub add_workgroup_user {
    my $self = shift;
    my $args = {
        @_
    };
    return;
}
sub get_workgroup_users {
    my $self = shift;
    my $args = {
        @_
    };
    return;
}
sub modify_workgroup_user {
    my $self = shift;
    my $args = {
        @_
    };
    return;
}
sub remove_workgroup_user {
    my $self = shift;
    my $args = {
        @_
    };
    return;
}

return 1;
