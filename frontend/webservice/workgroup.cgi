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

sub create_workgroup {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($ok, $access_err) = $user->has_system_access(role => 'normal');
    return (undef, $access_err) if defined $access_err;

    my ($wg, $wg_err) = $ac->create_workgroup(
        description => $params->{description}{value},
        external_id => $params->{external_id}{value},
        name        => $params->{name}{value},
        type        => $params->{type}{value}
    );
    if (defined $wg_err) {
        $method->set_error($wg_err);
        return;
    }
    return { results => [{ success => 1, workgroup_id => $wg->workgroup_id }] };
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

    my $err = $ac->delete_workgroup(workgroup_id => $params->{workgroup_id}{value});
    if (defined $err) {
        $method->set_error($err);
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
    return (undef, $access_err) if defined $access_err;

    my ($wg, $workgroup_err) = $ac->get_workgroup(
        workgroup_id => $params->{workgroup_id}{value}
    );
    if (defined $workgroup_err) {
        $method->set_error($workgroup_err);
        return;
    }
    return $wg->to_hash;
}

$ws->handle_request;
