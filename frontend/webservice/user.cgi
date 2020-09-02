#!/usr/bin/perl

use strict;
use warnings;

use GRNOC::WebService::Method;
use GRNOC::WebService::Dispatcher;
use OESS::DB;
use OESS::DB::User;
use OESS::VRF;


my $db = OESS::DB->new();
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

    my $result = OESS::User->new(db => $db, username => $ENV{'REMOTE_USER'});
    if (!defined $result) {
        $method->set_error("Couldn't find user $ENV{'REMOTE_USER'}.");
        return;
    }
    $result->load_workgroups;

    my $hash = $result->to_hash();
    $hash->{username} = $ENV{REMOTE_USER};
    return { results => [$hash] };
}

sub main{
    register_ro_methods();
    register_rw_methods();
    $svc->handle_request();
}

main();
