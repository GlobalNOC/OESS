#!/usr/bin/perl

use strict;
use warnings;

use GRNOC::WebService::Method;
use GRNOC::WebService::Dispatcher;

use OESS::AccessController::Default;
use OESS::DB;
use OESS::DB::User;
use OESS::User;


my $ws = new GRNOC::WebService::Dispatcher();

my $db = new OESS::DB();
my $ac = new OESS::AccessController::Default(db => $db);


my $create_workgroup = GRNOC::WebService::Method->new(
    name        => 'create_workgroup',
    description => 'create_workgroup adds a new workgroup to OESS',
    callback    => sub { create_workgroup(@_) }
);
$create_workgroup->add_input_parameter(
    name        => 'description',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'Description of workgroup'
);
$create_workgroup->add_input_parameter(
    name        => 'external_id',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'External ID of workgroup'
);
$create_workgroup->add_input_parameter(
    name        => 'name',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => 'Name of workgroup'
);
$create_workgroup->add_input_parameter(
    name        => 'type',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    default     => 'normal',
    description => 'Type of workgroup'
);
$ws->register_method($create_workgroup);

my $delete_workgroup = GRNOC::WebService::Method->new(
    name        => "delete_workgroup",
    description => "delete_workgroup deletes workgroup workgroup_id",
    callback    => sub { delete_workgroup(@_) }
);
$delete_workgroup->add_input_parameter(
    name        => 'workgroup_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'identifier used to lookup the workgroup'
);
$ws->register_method($delete_workgroup);

my $edit_workgroup = GRNOC::WebService::Method->new(
    name        => 'edit_workgroup',
    description => 'edit_workgroup edits workgroup workgroup_id',
    callback    => sub { edit_workgroup(@_) }
);
$edit_workgroup->add_input_parameter(
    name        => 'description',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'Description of workgroup'
);
$edit_workgroup->add_input_parameter(
    name        => 'external_id',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'External ID of workgroup'
);
$edit_workgroup->add_input_parameter(
    name        => 'name',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'Name of workgroup'
);
$edit_workgroup->add_input_parameter(
    name        => 'type',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'Type of workgroup'
);
$edit_workgroup->add_input_parameter(
    name        => 'workgroup_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'Identifier used to lookup the workgroup'
);
$ws->register_method($edit_workgroup);

my $get_workgroup = GRNOC::WebService::Method->new(
    name        => "get_workgroup",
    description => "get_workgroup returns workgroup workgroup_id",
    callback    => sub { get_workgroup(@_) }
);
$get_workgroup->add_input_parameter(
    name        => 'workgroup_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'identifier used to lookup the workgroup'
);
$ws->register_method($get_workgroup);

my $get_workgroup_users = GRNOC::WebService::Method->new(
    name        => "get_workgroup_users",
    description => "get_workgroup_users returns the users of workgroup workgroup_id",
    callback    => sub { get_workgroup_users(@_) }
);
$get_workgroup_users->add_input_parameter(
    name        => 'workgroup_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'identifier used to lookup the workgroup'
);
$ws->register_method($get_workgroup_users);

my $modify_workgroup_user = GRNOC::WebService::Method->new(
    name        => "modify_workgroup_user",
    description => "modify_workgroup_user modifies the user's workgroup membership",
    callback    => sub { modify_workgroup_user(@_) }
);
$modify_workgroup_user->add_input_parameter(
    name        => 'user_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'identifier used to lookup the user'
);
$modify_workgroup_user->add_input_parameter(
    name        => 'workgroup_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'identifier used to lookup the workgroup'
);
$modify_workgroup_user->add_input_parameter(
    name        => 'role',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => "user's workgroup role"
);
$ws->register_method($modify_workgroup_user);

my $remove_workgroup_user = GRNOC::WebService::Method->new(
    name        => "remove_workgroup_user",
    description => "remove_workgroup_user removes a user from the specified workgroup",
    callback    => sub { remove_workgroup_user(@_) }
);
$remove_workgroup_user->add_input_parameter(
    name        => 'user_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'identifier used to lookup the user'
);
$remove_workgroup_user->add_input_parameter(
    name        => 'workgroup_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'identifier used to lookup the workgroup'
);
$ws->register_method($remove_workgroup_user);

my $add_workgroup_user = GRNOC::WebService::Method->new(
    name        => "add_workgroup_user",
    description => "add_workgroup_user adds a user from the specified workgroup",
    callback    => sub { add_workgroup_user(@_) }
);
$add_workgroup_user->add_input_parameter(
    name        => 'user_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'identifier used to lookup the user'
);
$add_workgroup_user->add_input_parameter(
    name        => 'workgroup_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'identifier used to lookup the workgroup'
);
$add_workgroup_user->add_input_parameter(
    name        => 'role',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => 'role of user in the workgroup'
);
$ws->register_method($add_workgroup_user);

sub create_workgroup {
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

    if (length($params->{name}{value}) > 20) {
        $method->set_error("Workgroup name cannot exceed 20 characters in length.");
        return;
    }

    my ($workgroup_id, $wg_err) = $ac->create_workgroup(
        description => $params->{description}{value},
        external_id => $params->{external_id}{value},
        name        => $params->{name}{value},
        type        => $params->{type}{value}
    );
    if (defined $wg_err) {
        $method->set_error($wg_err);
        return;
    }
    return { results => [{ success => 1, workgroup_id => $workgroup_id }] };
}

sub delete_workgroup {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($wg_access, undef) = $user->has_workgroup_access(
        role         => 'admin',
        workgroup_id => $params->{workgroup_id}{value},
    );
    my ($sys_access, undef) = $user->has_system_access(role => 'normal');
    if (!$wg_access && !$sys_access) {
        $method->set_error("User $ENV{REMOTE_USER} not authorized.");
        return;
    }

    my $wg_err = $ac->delete_workgroup(workgroup_id => $params->{workgroup_id}{value});
    if (defined $wg_err) {
        $method->set_error($wg_err);
        return;
    }
    return { results => [{ success => 1 }] };
}

sub edit_workgroup {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($wg_access, undef) = $user->has_workgroup_access(
        role         => 'admin',
        workgroup_id => $params->{workgroup_id}{value},
    );
    my ($sys_access, undef) = $user->has_system_access(role => 'normal');
    if (!$wg_access && !$sys_access) {
        $method->set_error("User $ENV{REMOTE_USER} not authorized.");
        return;
    }

    if (!defined $params->{description}{value} && $params->{description}{is_set}) {
        $params->{description}{value} = "";
    }
    if (!defined $params->{external_id}{value} && $params->{external_id}{is_set}) {
        $params->{external_id}{value} = "";
    }

    if (length($params->{name}{value}) > 20) {
        $method->set_error("Workgroup name cannot exceed 20 characters in length.");
        return;
    }

    my $wg_err = $ac->edit_workgroup(
        description  => $params->{description}{value},
        external_id  => $params->{external_id}{value},
        name         => $params->{name}{value},
        type         => $params->{type}{value},
        workgroup_id => $params->{workgroup_id}{value}
    );
    if (defined $wg_err) {
        $method->set_error($wg_err);
        return;
    }
    return { results => [{ success => 1 }] };
}

sub get_workgroup {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($ok, $access_err) = $user->has_workgroup_access(
        role         => 'read-only',
        workgroup_id => $params->{workgroup_id}{value},
    );
    if (defined $access_err) {
        $method->set_error($access_err);
        return;
    }

    my ($wg, $workgroup_err) = $ac->get_workgroup(
        workgroup_id => $params->{workgroup_id}{value}
    );
    if (defined $workgroup_err) {
        $method->set_error($workgroup_err);
        return;
    }
    return $wg->to_hash;
}

sub get_workgroup_users {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($ok, $access_err) = $user->has_workgroup_access(
        role         => 'read-only',
        workgroup_id => $params->{workgroup_id}{value},
    );
    if (defined $access_err) {
        $method->set_error($access_err);
        return;
    }

    my ($users, $users_err) = $ac->get_workgroup_users(
        workgroup_id => $params->{workgroup_id}{value}
    );
    if (defined $users_err) {
        $method->set_error($users_err);
        return;
    }

    my $result = [];
    foreach my $user (@$users) {
        push @$result, $user->to_hash;
    }

    return $result;
}

sub modify_workgroup_user {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($ok, $access_err) = $user->has_workgroup_access(
        role         => 'admin',
        workgroup_id => $params->{workgroup_id}{value},
    );
    if (defined $access_err) {
        $method->set_error($access_err);
        return;
    }

    my $modify_err = $ac->modify_workgroup_user(
        user_id => $params->{user_id}{value},
        workgroup_id => $params->{workgroup_id}{value},
        role => $params->{role}{value}
    );
    if (defined $modify_err) {
        $method->set_error($modify_err);
        return;
    }

    return { results => [{ success => 1 }] };
}

sub remove_workgroup_user {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($ok, $access_err) = $user->has_workgroup_access(
        role         => 'admin',
        workgroup_id => $params->{workgroup_id}{value},
    );
    if (defined $access_err) {
        $method->set_error($access_err);
        return;
    }

    my $remove_err = $ac->remove_workgroup_user(
        user_id => $params->{user_id}{value},
        workgroup_id => $params->{workgroup_id}{value}
    );
    if (defined $remove_err) {
        $method->set_error($remove_err);
        return;
    }

    return { results => [{ success => 1 }] };
}

sub add_workgroup_user {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($ok, $access_err) = $user->has_workgroup_access(
        role         => 'admin',
        workgroup_id => $params->{workgroup_id}{value},
    );
    if (defined $access_err) {
        $method->set_error($access_err);
        return;
    }

    my $add_err = $ac->add_workgroup_user(
        user_id      => $params->{user_id}{value},
        workgroup_id => $params->{workgroup_id}{value},
        role         => $params->{role}{value}
    );
    if (defined $add_err) {
        $method->set_error($add_err);
        return;
    }

    return { results => [{ success => 1 }] };
}

$ws->handle_request;
