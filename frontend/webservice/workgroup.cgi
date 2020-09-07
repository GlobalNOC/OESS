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
