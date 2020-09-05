package OESS::AccessController::Default;

use strict;
use warnings;

use OESS::DB;
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

sub delete_user { return; }
sub edit_user { return; }

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

sub get_users { return; }
sub get_user_workgroups { return; }

sub create_workgroup { return; }
sub delete_workgroup { return; }
sub edit_workgroup { return; }

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

sub get_workgroups { return; }

sub add_workgroup_user { return; }
sub get_workgroup_users { return; }
sub modify_workgroup_user { return; }
sub remove_workgroup_user { return; }

return 1;
