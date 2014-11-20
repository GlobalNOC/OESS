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
use Log::Log4perl;

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

    my $workgroup_id = $cgi->param('workgroup_id') || undef;
    my $workgroup_name;
    if (!defined $workgroup_id){
        $workgroup_name = "all workgroups";
    }
    elsif ($db->get_user_admin_status(username=> $username)->[0]{'is_admin'}){
        $workgroup_name = $db->get_workgroups(workgroup_id => $workgroup_id)->[1]{'name'};
    }
    else {
        $workgroup_name = $db->get_workgroups(workgroup_id => $workgroup_id)->[0]{'name'};
    }

    my $interface_name = $db->get_interface(interface_id => $cgi->param("interface_id"))->{'name'};
    my $vlan_start = $cgi->param("vlan_start");
    my $vlan_end = $cgi->param("vlan_end");
    my $init_logger = Log::Log4perl->init_and_watch('/etc/oess/logging.conf'); 
    my $logger = Log::Log4perl->get_logger("OESS.ACL");
    $logger->debug("Initiating creation of ACL at <time> for ");    
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
        my $time = localtime();
        $logger->error("Error creating ACL at $time for $workgroup_name, on $interface_name from vlans $vlan_start to $vlan_end. Action was initiated by $username");
        $results->{'error'} = $db->get_error();
        $results->{'results'} = [ { success => 0 } ];
    }
    else {
        my $time = localtime();
        $logger->info("Created ACL with id $acl_id at $time for $workgroup_name on $interface_name from vlans $vlan_start to $vlan_end, Action was initiated by $username");
        $results->{'results'} = [{ 
            success => 1, 
            interface_acl_id => $acl_id 
        }];
    }

    return $results;
}

sub update_acl {
    my $results;

    my $acl_id = $cgi->param("interface_acl_id");
    my $original_values =  get_acls($acl_id)->{'results'}[0];
    my $original_workgroup_name;
    if ($original_values->{'workgroup_id'}){
        $original_workgroup_name = $db->get_workgroup_by_id(workgroup_id => $original_values->{'workgroup_id'})->{'name'};
    }
    else{
        $original_workgroup_name = "All workgroups";
    }
    my $original_interface_name = $db->get_interface(interface_id => $original_values->{"interface_id"})->{'name'};;
 
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

    my $workgroup_id = $cgi->param('workgroup_id');
    my $workgroup_name;
    if ($workgroup_id){
        $workgroup_name = $db->get_workgroup_by_id(workgroup_id => $workgroup_id)->{'name'};
    }
    else{
        $workgroup_name = "All workgroups";
    }
    my $interface_name = $db->get_interface(interface_id => $cgi->param("interface_id"))->{'name'}; 
    my $vlan_start = $cgi->param("vlan_start");
    my $vlan_end = $cgi->param("vlan_end");
    my $init_logger = Log::Log4perl->init_and_watch('/etc/oess/logging.conf'); 
    my $logger = Log::Log4perl->get_logger("OESS.ACL");
    
    if ( !defined $success ) {
        my $time = localtime();
        $logger->info("Failed to update acl with id $acl_id, at $time on $interface_name. Action was initiated by $username."); 
        $results->{'error'}   = $db->get_error();
        $results->{'results'} = [];
    }

    else {
        #get the passed values
        my @passed_values = $cgi->param;
        my $passed_values_hash;
        foreach my $passed_value (@passed_values) {

            #we don't need the action param
            if ($passed_value eq "action" || $passed_value eq "notes") {
                next;
            }
            $passed_values_hash->{$passed_value} = $cgi->param($passed_value);
        }

        #we don't need certain key-values in the original hash
        delete $original_values->{'interface_name'}; delete $original_values->{'owner_workgroup_name'}; delete $original_values->{'interface_acl_id'}; delete $original_values->{'workgroup_name'};
        delete $original_values->{'notes'}; delete $original_values->{'owner_workgroup_id'};

        #nor do we need certain values in the passed value hash
        delete $passed_values_hash->{'interface_acl_id'};
        
        #delete values from both hashes that didn't change.
        foreach my $key ( sort keys %$original_values ) {
            
            #if we are keeping the workgroup set to all
            if (!defined $original_values->{$key} && !$passed_values_hash->{$key}){
            
                delete($original_values->{$key});
                delete($passed_values_hash->{$key});
            }
            #if we are changing the workgroup TO all
            if (defined $original_values->{$key} && !$passed_values_hash->{$key}){
                $passed_values_hash->{'workgroup id'} = "All workgroups";
            }
            if ($original_values->{$key} eq $passed_values_hash->{$key}){
    
                delete($original_values->{$key});
                delete($passed_values_hash->{$key});

               }
          }

        my @original_array = _convert_hash_to_array($original_values, $original_interface_name, $original_workgroup_name);
        my @updated_array = _convert_hash_to_array($passed_values_hash, $interface_name, $workgroup_name);

        my $time = localtime();
        $logger->info("Updated ACL with id $acl_id, at $time on $interface_name. Action was initiated by $username.");
        
        #now compare and contrast values
        $logger->info("Original values for the ACL were: " . _print_formatted_array(@original_array));
        $logger->info("New values for the ACL were: " . _print_formatted_array(@updated_array));
        $results->{'results'} = [ { success => 1 } ];
    }

    return $results;

}

sub remove_acl {
    my $results;
    my $init_logger = Log::Log4perl->init_and_watch('/etc/oess/logging.conf');
    my $logger = Log::Log4perl->get_logger("OESS.ACL");
 
    my $interface_acl_id   = $cgi->param('interface_acl_id');
    
    my $result = $db->remove_acl(
        user_id      => $user_id,
        interface_acl_id => $interface_acl_id
    );

    if ( !defined $result ) {
        my $time = localtime();
        $logger->info("Failed to delete ACL with id $interface_acl_id at $time.  Action was initiated by $username.");
        $results->{'error'}   = $db->get_error();
        $results->{'results'} = [];
    }
    else {
        my $time = localtime();
        $logger->info("Deleted ACL with id $interface_acl_id at $time.  Action was initiated by $username.");
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


sub _convert_hash_to_array {
    my($hash, $interface_name, $wkgroup_name) = @_;
    my $convert_interface_id =0;
    my $convert_workgroup_id=0;
    my @array;
    foreach my $key (%$hash) {
        if ($convert_workgroup_id){
            $key = $wkgroup_name;    
            $convert_workgroup_id =0; 
        }
        if ($key eq "workgroup_id"){
            $key = "workgroup";
            #next value will be the workgroup ID, so turn on the flag, and handle it when it comes.
            $convert_workgroup_id = 1;
        }

        if($convert_interface_id){
            $key = $interface_name;
            $convert_interface_id = 0;
        }

        if ($key eq "interface_id"){
            $key = "Interface";
            $convert_interface_id = 1;
        }

        push (@array, $key);

    }
    return @array;
}

#this formats the original value and new value arrays into a format that looks pretty for the logs.
sub _print_formatted_array {

    my @array = @_;
    my $string;
    my $count = 0;
    foreach my $element (@array){
        #if the count is on an even number, we are on a value name, so we format it like so. 
        if (0 == $count % 2) {
            $string .= "$element->";
        }
        #other wise, it is the value itself, so we format it like this.
        else {
            $string .= "$element ";
        }
        $count = $count + 1;
    }
    return $string;

}

main();

