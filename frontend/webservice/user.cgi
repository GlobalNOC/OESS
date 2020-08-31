#!/usr/bin/perl

use strict;
use warnings;

use GRNOC::WebService::Method;
use GRNOC::WebService::Dispatcher;

use OESS::DB;
use OESS::AccessController::Default;

my $db = new OESS::DB();
my $ac = new OESS::AccessController::Default(db => $db);

my $svc = GRNOC::WebService::Dispatcher->new();


sub register_ro_methods{
    my $method = GRNOC::WebService::Method->new(
        name => "get_current",
        description => "returns details of the current user",
        callback => sub { get_current(@_) }
    );
    $svc->register_method($method);
}

sub register_rw_methods{

}

sub get_current {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(
        username => $ENV{'REMOTE_USER'}
    );
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    $user->load_workgroups;
    return { results => [ $user->to_hash ] };
}

sub main{
    register_ro_methods();
    register_rw_methods();
    $svc->handle_request();
}

main();
