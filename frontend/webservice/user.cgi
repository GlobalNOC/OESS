#!/usr/bin/perl

use strict;
use warnings;

use GRNOC::WebService::Method;
use GRNOC::WebService::Dispatcher;

use OESS::AccessController::Default;
use OESS::DB;


my $ws = new GRNOC::WebService::Dispatcher();

my $db = new OESS::DB();
my $ac = new OESS::AccessController::Default(db => $db);


my $create_user = GRNOC::WebService::Method->new(
    name        => "create_user",
    description => "create_user adds a new user to OESS",
    callback    => sub { create_user(@_) }
);
$create_user->add_input_parameter(
    name        => 'email',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => 'Email address of user'
);
$create_user->add_input_parameter(
    name        => 'first_name',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => 'First name of user'
);
$create_user->add_input_parameter(
    name        => 'last_name',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => 'Last name of user'
);
$create_user->add_input_parameter(
    name        => 'username',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => 'Username of user'
);
$ws->register_method($create_user);

my $delete_user = GRNOC::WebService::Method->new(
    name        => "delete_user",
    description => "delete_user deletes user user_id",
    callback    => sub { delete_user(@_) }
);
$delete_user->add_input_parameter(
    name        => 'user_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'identifier used to lookup the user'
);
$ws->register_method($delete_user);

my $edit_user = GRNOC::WebService::Method->new(
    name        => "edit_user",
    description => "edit_user modifies an existing OESS user",
    callback    => sub { edit_user(@_) }
);
$edit_user->add_input_parameter(
    name        => 'email',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'Email address of user'
);
$edit_user->add_input_parameter(
    name        => 'first_name',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'First name of user'
);
$edit_user->add_input_parameter(
    name        => 'last_name',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'Last name of user'
);
$edit_user->add_input_parameter(
    name        => 'username',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    multiple    => 1,
    description => 'Username of user'
);
$edit_user->add_input_parameter(
    name        => 'user_id',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => 'UserId of user'
);
$ws->register_method($edit_user);

my $get_current = GRNOC::WebService::Method->new(
    name        => "get_current",
    description => "get_current returns the currently logged in user",
    callback    => sub { get_current(@_) }
);
$ws->register_method($get_current);

my $get_user = GRNOC::WebService::Method->new(
    name        => "get_user",
    description => "get_user returns the requested user",
    callback    => sub { get_user(@_) }
);
$get_user->add_input_parameter(
    name        => 'user_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 0,
    description => 'UserId of user'
);
$get_user->add_input_parameter(
    name        => 'username',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'Username of user'
);
$ws->register_method($get_user);

my $get_users = GRNOC::WebService::Method->new(
    name        => "get_users",
    description => "get_users returns a list of all users",
    callback    => sub { get_users(@_) }
);
$ws->register_method($get_users);

sub get_current {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    $user->load_workgroups;
    return { results => [ $user->to_hash ] };
}

sub create_user {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($ok, $access_err) = $user->has_system_access(role => 'normal');
    if (defined $access_err) {
        $method->set_error($access_err);
        return;
    }

    my ($user_id, $user_err) = $ac->create_user(
        email      => $params->{email}{value},
        first_name => $params->{first_name}{value},
        last_name  => $params->{last_name}{value},
        username   => $params->{username}{value}
    );
    if (defined $user_err) {
        $method->set_error($user_err);
        return;
    }
    return { results => [{ success => 1, user_id => $user_id }] };
}

sub delete_user {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my ($sys_access, undef) = $user->has_system_access(role => 'normal');
    if ($params->{user_id}{value} != $user->user_id && !$sys_access) {
        $method->set_error("User $ENV{REMOTE_USER} not authorized.");
        return;
    }

    my $user_err = $ac->delete_user(user_id => $params->{user_id}{value});
    if (defined $user_err) {
        $method->set_error($user_err);
        return;
    }

    return { results => [{ success => 1 }] };
}

sub edit_user {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $has_access = 0;
    if ($user->user_id eq $params->{user_id}{value}) {
        $has_access = 1;
    }
    my ($ok, undef) = $user->has_system_access(role => 'normal');
    if ($ok) {
        $has_access = 1;
    }
    if (!$has_access) {
        $method->set_error("User $ENV{REMOTE_USER} not authorized.");
        return;
    }

    my ($user2, $user_err) = $ac->edit_user(
        user_id    => $params->{user_id}{value},
        email      => $params->{email}{value},
        first_name => $params->{first_name}{value},
        last_name  => $params->{last_name}{value},
        usernames  => $params->{username}{value}
    );
    if (defined $user_err) {
        $method->set_error($user_err);
        return;
    }
    return { results => [{ success => 1, user_id => $params->{user_id}{value} }] };
}

sub get_user {
    my $method = shift;
    my $params = shift;

    if (!defined $params->{user_id}{value} && !defined $params->{username}{value}) {
        $method->set_error("get_user requires username or user_id.");
        return;
    }

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    # Logged in user requested itself
    if (defined $params->{user_id}{value} && $params->{user_id}{value} == $user->user_id) {
        return $user->to_hash;
    }
    if (defined $params->{username}{value} && $user->has_username($params->{username}{value})) {
        return $user->to_hash;
    }

    # Logged in requested info for another user
    my ($ok, $access_err) = $user->has_system_access(role => 'read-only');
    if (defined $access_err) {
        $method->set_error($access_err);
        return;
    }

    my ($user2, $user2_err) = $ac->get_user(
        user_id  => $params->{user_id}{value},
        username => $params->{username}{value}
    );
    if (defined $user2_err) {
        $method->set_error($user2_err);
        return;
    }
    $user2->load_workgroups;
    return $user2->to_hash;
}

sub get_users {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my ($users, $users_err) = $ac->get_users();
    if (defined $users_err) {
        $method->set_error($users_err);
        return;
    }
    
    my $result = [];
    foreach my $user (@$users) {
        push @$result, $user->to_hash;
    }
    return { results => $result };
}

$ws->handle_request;
