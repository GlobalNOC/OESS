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


my $get_current = GRNOC::WebService::Method->new(
    name        => "get_current",
    description => "get_current returns the currently logged in user",
    callback    => sub { get_current(@_) }
);
$ws->register_method($get_current);

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
    return (undef, $access_err) if defined $access_err;

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

$ws->handle_request;
