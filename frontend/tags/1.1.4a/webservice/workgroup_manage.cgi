#!/usr/bin/perl -T
#
##----- NDDI OESS Data.cgi
##
## Copyright 2011 Trustees of Indiana University
##
##   Licensed under the Apache License, Version 2.0 (the "License");
##  you may not use this file except in compliance with the License.
##   You may obtain a copy of the License at
##
##       http://www.apache.org/licenses/LICENSE-2.0
##
##   Unless required by applicable law or agreed to in writing, software
##   distributed under the License is distributed on an "AS IS" BASIS,
##   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
##   See the License for the specific language governing permissions and
##   limitations under the License.
#
use strict;
use warnings;

use CGI;
use JSON;
use Switch;
use Data::Dumper;

use URI::Escape;
use MIME::Lite;
use OESS::Database;

my $db   = new OESS::Database();

my $cgi = new CGI;

my $username = $ENV{'REMOTE_USER'};
my $user_id;

$| = 1;

sub main {

    if ( !$db ) {
        send_json( { "error" => "Unable to connect to database." } );
        exit(1);
    }

    $user_id = $db->get_user_id_by_auth_name( 'auth_name' => $username );

    my $user = $db->get_user_by_id( user_id => $user_id)->[0];

    my $action = $cgi->param('action');

    my $output;

    switch ($action) {
        case "get_all_workgroups" {
            $output = &get_all_workgroups();
        }
        case "get_acls" {
            $output = &get_acls();
        }
        case "add_acl" {
            if($user->{'type'} eq 'read-only'){
                send_json({error => 'Error: you are a readonly user'});
            }
            $output = &add_acl();
        }
        case "update_acl" {
            if($user->{'type'} eq 'read-only'){
                send_json({error => 'Error: you are a readonly user'});
            }
            $output = &update_acl();
        }
        case "remove_acl" {
            if($user->{'type'} eq 'read-only'){
                send_json({error => 'Error: you are a readonly user'});
            }
            $output = &remove_acl();
        }
        else {
            $output->{'error'}   = "Error: No Action specified";
            $output->{'results'} = [];
        }
    }

    send_json($output);

}

sub get_all_workgroups {
    my $results;

    my $workgroups = $db->get_all_workgroups();

    return parse_results( res => $workgroups );
}

sub get_acls {
    my $results;

    my %params;
    if($cgi->param('interface_id')){
        $params{'interface_id'} = $cgi->param('interface_id');
    }
    if($cgi->param('interface_acl_id')){
        $params{'interface_acl_id'} = $cgi->param('interface_acl_id');
    }
    
    my $acls = $db->get_acls( %params );

    return parse_results( res => $acls );
}

sub add_acl {
    my $results;

    my $acl_id = $db->add_acl( 
        workgroup_id  => $cgi->param("workgroup_id") || undef,
        interface_id  => $cgi->param("interface_id"),
        allow_deny    => $cgi->param("allow_deny"),
        eval_position => $cgi->param("eval_position") || undef,
        vlan_start    => $cgi->param("vlan_start"),
        vlan_end      => $cgi->param("vlan_end") || undef,
        notes         => $cgi->param("notes") || undef,
        user_id       => $user_id
    );

    if ( !defined $acl_id ) {
        $results->{'error'} = $db->get_error();
        $results->{'results'} = [ { success => 0 } ];
    }
    else {
        $results->{'results'} = [{ 
            success => 1, 
            interface_acl_id => $acl_id 
        }];
    }

    return $results;
}

sub update_acl {
    my $results;

    my $success = $db->update_acl(
        interface_acl_id => $cgi->param("interface_acl_id"),
        workgroup_id     => $cgi->param("workgroup_id") || undef,
        interface_id     => $cgi->param("interface_id"),
        allow_deny       => $cgi->param("allow_deny"),
        eval_position    => $cgi->param("eval_position"),
        vlan_start       => $cgi->param("vlan_start"),
        vlan_end         => $cgi->param("vlan_end") || undef,
        notes            => $cgi->param("notes") || undef,
        user_id          => $user_id
    );

    if ( !defined $success ) {
        $results->{'error'}   = $db->get_error();
        $results->{'results'} = [];
    }
    else {
        $results->{'results'} = [ { success => 1 } ];
    }

    return $results;

}

sub remove_acl {
    my $results;

    my $interface_acl_id   = $cgi->param('interface_acl_id');

    my $result = $db->remove_acl(
        user_id      => $user_id,
        interface_acl_id => $interface_acl_id
    );

    if ( !defined $result ) {
        $results->{'error'}   = $db->get_error();
        $results->{'results'} = [];
    }
    else {
        $results->{'results'} = [ { success => 1 } ];
    }

    return $results;
}

sub parse_results {
    my %args = @_;

    my $res = $args{'res'};
    my $results;
     
    if ( !defined $res ) {
        $results->{'error'} = $db->get_error();
    }else {
        $results->{'results'} = $res;
    }

    return $results;
}

sub send_json {
    my $output = shift;
    print "Content-type: text/plain\n\n" . encode_json($output);
}

main();

