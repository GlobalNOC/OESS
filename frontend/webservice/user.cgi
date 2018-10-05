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
        name => "get_user_details",
        description => "returns the details of a specified user",
        callback => sub { get_user_details(@_) }
    );
    $method->add_input_parameter(
        name => 'user_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
        description => 'VRF ID to fetch details'
    );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name => "get_current",
        description => "returns details of the current user",
        callback => sub { get_current(@_) }
    );
    $svc->register_method($method);
}

sub register_rw_methods{
    
}

sub get_user_details{
    my $method = shift;
    my $params = shift;

    my $user_id = $params->{'user_id'}{'value'};
    
    my $user = OESS::User->new(db => $db, user_id => $user_id);

    if(!defined($user)){
        $method->set_error("Unable to find user: " . $user_id);
        return;
    }

    return {results => [$user->to_hash()]};
}

sub get_current {
    my $method = shift;
    my $params = shift;

    my $user = OESS::DB::User::find_user_by_remote_auth(
        db          => $db,
        remote_user => $ENV{'REMOTE_USER'}
    );

    my $result = OESS::User->new(db => $db, user_id => $user->{user_id});
    if (!defined $user) {
        $method->set_error("Couldn't find user $ENV{'REMOTE_USER'}.");
        return;
    }

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
