#!/usr/bin/perl

use strict;
use warnings;

use AnyEvent;

use GRNOC::WebService::Method;
use GRNOC::WebService::Dispatcher;

use OESS::AccessController::Default;
use OESS::Config;
use OESS::DB;
use OESS::Link;

my $config = new OESS::Config(config_filename => '/etc/oess/database.xml');
my $db = new OESS::DB(config_obj => $config);
my $ac = new OESS::AccessController::Default(db => $db);
my $ws = new GRNOC::WebService::Dispatcher();

#For now just a get all links function possibly add filtering later
my $get_links = GRNOC::WebService::Method->new(
    name        => "get_links",
    description => "Gathers all the links and returns them",
    callback    => sub { get_links(@_) }
);
$ws->register_method($get_links);

my $get_link = GRNOC::WebService::Method->new(
    name        => "get_link",
    description => "Gets a single link based on the params passed",
    callback    => sub { get_link(@_) }
);
$get_link->add_input_parameter(
    name        => 'link_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'link id of a link'
);

$ws->register_method($get_link);


my $edit_link = GRNOC::WebService::Method->new(
    name        => "edit_link",
    description => "Gets a single link based on the params passed",
    callback    => sub { get_link(@_) }

);

$edit_link->add_input_parameter(
    name        => 'link_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'Link id of the link'
    );
$edit_link->add_input_parameter(
    name        => 'link_state',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'State of the link either active or decom'
    );
$edit_link->add_input_parameter(
    name        => 'interface_a_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 0,
    description => 'first interface id of the link'
    );
$edit_link->add_input_parameter(
    name        => 'ip_a',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'first interface id of the link'
    );
$edit_link->add_input_parameter(
    name        => 'interface_z_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 0,
    description => 'second interface id of the link'
    );
$edit_link->add_input_parameter(
    name        => 'ip_z',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'second interface id of the link'
    );
$edit_link->add_input_parameter(
    name        => 'name',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'name of the link'
    );
$edit_link->add_input_parameter(
    name        => 'state',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => 'state of the link'
   );
$edit_link->add_input_parameter(
    name        => 'remote_urn',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => ''
    );
$edit_link->add_input_parameter(
    name        => 'metric',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 0,
    description => ''
    );
$ws->register_method($edit_link);

sub get_links {
    my ($links, $err) = OESS::DB::Link::fetch_all(db => $db);
    my $results = [];
    foreach my $link (@$links) {
        my $obj = new OESS::Link(db => $db, model => $link);
        push @$results, $obj->to_hash;
    }

    return { results => $results};
}

sub get_link {
    my $method = shift;
    my $params = shift;

    my ($link, $err) = OESS::DB::Link::fetch(db => $db, link_id => $params->{link_id}{value});
    if (!defined $link) {
        $method->set_error("Couldn't find link $params->{link_id}{value}");
        return;
    }
    return { results => $link };
}

sub edit_link {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my ($access_ok, $access_err) = $user->has_system_access(role => 'normal');
    if (defined $access_err) {
        $method->set_error($access_err);
        return;
    }

    my ($link, $edit_err) = new OESS::Link( db => $db, link_id => $params->{link_id}{value});
    if (!defined $link) {
        $method->set_error("Couldn't find link $params->{link_id}{value}");
        return;
    }

    if (defined $params->{link_state}{value}){
        $link->link_state($params->{link_state}{value});
    }
    if (defined $params->{interface_a_id}{value}){
        $link->interface_a_id($params->{interface_a_id}{value});
    }
    if (defined $params->{ip_a}{value}){
        $link->ip_a($params->{ip_a}{value});
    }
    if (defined $params->{interface_z_id}{value}){
        $link->interface_z_id($params->{interface_z_id}{value});
    }
    if (defined $params->{ip_z}{value}){
        $link->ip_z($params->{ip_z}{value});
    }
    if (defined $params->{name}{value}){
        $link->name($params->{name}{value});
    }
    if (defined $params->{status}{value}){
        $link->status($params->{status}{value});
    }
    if (defined $params->{remote_urn}{value}){
        $link->remote_urn($params->{remote_urn}{value});
    }
    if (defined $params->{metric}{value}){
        $link->metric($params->{metric}{value});
    }
    my $ok = $link->update;
    if(defined $ok) {
        $ok = 0;
    }
    return { results => [{ success => $ok }] };
}

$ws->handle_request;
