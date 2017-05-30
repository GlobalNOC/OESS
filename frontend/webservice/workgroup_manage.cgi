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
use GRNOC::WebService;

Log::Log4perl::init_and_watch('/etc/oess/logging.conf');

my $db   = new OESS::Database();

#register web service dispatcher
my $svc = GRNOC::WebService::Dispatcher->new(method_selector => ['method', 'action']);

my $username = $ENV{'REMOTE_USER'};
my $user_id;

$| = 1;

sub main {

    if ( !$db ) {
        send_json( { "error" => "Unable to connect to database." } );
        exit(1);
    }

    if ( !$svc ){
	send_json( {"error" => "Unable to access GRNOC::WebService" });
	exit(1);
    }

    $user_id = $db->get_user_id_by_auth_name( 'auth_name' => $username );

    my $user = $db->get_user_by_id( user_id => $user_id)->[0];
    
 
    if ($user->{'status'} eq 'decom') {
	send_json("error");
	exit(1);
    }
    
    if ($user->{'type'} eq 'read-only') {
	send_json("Error: you are a readonly user");
	return;
    }

    #register the WebService Methods
    register_webservice_methods();

    #handle the WebService request.
    $svc->handle_request();

}

sub register_webservice_methods {
    
    my $method;
    
    #get_all_workgroups()
     $method = GRNOC::WebService::Method->new(
	 name            => "get_all_workgroups",
	 description     => "returns a list of workgroups the logged in user has access to",
	 callback        => sub { get_all_workgroups( @_ ) }
	 );

    #register get_workgroups() method
    $svc->register_method($method);

    #get_acls
    $method = GRNOC::WebService::Method->new(
	name            => "get_acls",
	description     => "Returns a JSON formatted list of ACLs for a given interface.",
	callback        => sub { get_acls( @_ ) }
	);

    #add the optional input parameter interface_id
    $method->add_input_parameter(
        name            => 'interface_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "The interface ID for which the user wants the acl details."
	);

    #add the optional input parameter interface_acl_id
    $method->add_input_parameter(
        name            => 'interface_acl_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "The interface acl ID for which the user wants the details."
	);

    #register the get_acls() method
    $svc->register_method($method);

    #add_acl
    $method = GRNOC::WebService::Method->new(
	name            => "add_acl",
	description     => "Adds an ACL for a specific interface/workgroup combination",
	callback        => sub { add_acl( @_ ) }
	);

    #add the optional input parameter workgroup_id
    $method->add_input_parameter(
	name            => 'workgroup_id',
	pattern         => $GRNOC::WebService::Regex::INTEGER,
	required        => 0,
	description     => "the workgroup the ACL is applied to."
	); 

    #add the required input parameter interface_id
    $method->add_input_parameter(
        name            => 'interface_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "Specific interface_ id add the ACL to"
        );
    
    #add the required input parameter allow_deny
     $method->add_input_parameter(
        name            => 'allow_deny',
        pattern         => '^(allow|deny)',
        required        => 1,
        description     => "if the ACL is an allow or deny rule."
	 );

    #add the optional input parameter eval_position
     $method->add_input_parameter(
        name            => 'eval_position',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "the position in the ACL list where the rule will be evaluated."
	 );

    #add the required input paramter vlan_start
    $method->add_input_parameter(
        name            => 'vlan_start',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "the start vlan tag."
        );
    
    #add the optional input paramter vlan_end
    $method->add_input_parameter(
        name            => 'vlan_end',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "the end vlan tag."
        );
    
    #add the optional input paramter notes
    $method->add_input_parameter(
        name            => 'notes',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 0,
        description     => "Any notes or reason for the ACL."
        );
    
    #register the add_acl() method.
    $svc->register_method($method);
    
    #update_acl
    $method = GRNOC::WebService::Method->new(
        name            => "update_acl",
        description     => "Updates an ACL for a specific interface/workgroup combination",
        callback        => sub { update_acl( @_ ) }
        );

    #add the optional input parameter workgroup_id
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "the workgroup the ACL is applied to."
        );

    #add the required input parameter interface_id
    $method->add_input_parameter(
        name            => 'interface_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "Specific interface_ id add the ACL to"
        );

    #add the optional input parameter interface_acl_id
    $method->add_input_parameter(
        name            => 'interface_acl_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The interface acl ID of the ACL to be modified."
        );


    #add the required input parameter allow_deny
     $method->add_input_parameter(
        name            => 'allow_deny',
        pattern         => '^(allow|deny)',
        required        => 1,
        description     => "if the ACL is an allow or deny rule."
         );

    #add the required input parameter eval_position
     $method->add_input_parameter(
        name            => 'eval_position',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "the position in the ACL list where the rule will be evaluated."
         );

    #add the required input paramter vlan_start
    $method->add_input_parameter(
        name            => 'vlan_start',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "the start vlan tag."
        );

    #add the optional input paramter vlan_end
    $method->add_input_parameter(
        name            => 'vlan_end',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "the end vlan tag."
        );

    #add the optional input paramter notes
    $method->add_input_parameter(
        name            => 'notes',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 0,
        description     => "Any notes or reason for the ACL."
        );

    #register the update_acl() method.
    $svc->register_method($method);

    #remove_acl
    $method = GRNOC::WebService::Method->new(
	name            => "remove_acl",
	description     => "removes an existing ACL",
	callback        => sub { remove_acl( @_ ) }
	);

    #add the required input parameter interface_acl_id
    $method->add_input_parameter(
        name            => 'interface_acl_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The interface acl ID the ACL to be removed."
        );

    #register the remove_acl() method
    $svc->register_method($method);

}

sub get_all_workgroups {
    
    my ( $method, $args ) = @_ ;
    my $results;

    my $workgroups = $db->get_all_workgroups();

    return parse_results( res => $workgroups, method => $method );
}

sub get_acls {
    
    my ( $method, $args ) = @_ ;
    my $results;

    my %params;
    if($args->{'interface_id'}{'value'}){
        $params{'interface_id'} = $args->{'interface_id'}{'value'};
    }
    if($args->{'interface_acl_id'}{'value'}){
        $params{'interface_acl_id'} = $args->{'interface_acl_id'}{'value'};
    }
    
    my $acls = $db->get_acls( %params );
    
    return parse_results( res => $acls , method => $method);
}

sub add_acl {
    
    my ( $method, $args ) = @_ ;
    my $results;

    my $workgroup_id = $args->{'workgroup_id'}{'value'} || undef;
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

    my $interface_name = $db->get_interface(interface_id => $args->{"interface_id"}{'value'})->{'name'};
    my $vlan_start = $args->{"vlan_start"}{'value'};
    my $vlan_end = $args->{"vlan_end"}{'value'};
    my $logger = Log::Log4perl->get_logger("OESS.ACL");
    $logger->debug("Initiating creation of ACL at <time> for ");    
    my $acl_id = $db->add_acl( 
        workgroup_id  => $args->{"workgroup_id"}{'value'} || undef,
        interface_id  => $args->{"interface_id"}{'value'},
        allow_deny    => $args->{"allow_deny"}{'value'},
        eval_position => $args->{"eval_position"}{'value'} || undef,
        vlan_start    => $args->{"vlan_start"}{'value'},
        vlan_end      => $args->{"vlan_end"}{'value'} || undef,
        notes         => $args->{"notes"}{'value'} || undef,
        user_id       => $user_id
    );
    if ( !defined $acl_id ) {
        $logger->error("Error creating ACL at ". localtime(). " for $workgroup_name, on $interface_name from vlans $vlan_start to $vlan_end. Action was initiated by $username");
	$method->set_error( $db->get_error() );
	return;
    }
    else {
        $logger->info("Created ACL with id $acl_id at " .localtime(). " for $workgroup_name on $interface_name from vlans $vlan_start to $vlan_end, Action was initiated by $username");
        $results->{'results'} = [{ 
            success => 1, 
            interface_acl_id => $acl_id 
        }];
    }

    return $results;
}

sub update_acl {
    my ( $method, $args ) = @_ ;
    my $results;

    my $acl_id = $args->{"interface_acl_id"}{'value'};
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
        interface_acl_id => $args->{"interface_acl_id"}{'value'},
        workgroup_id     => $args->{"workgroup_id"}{'value'} || undef,
        interface_id     => $args->{"interface_id"}{'value'},
        allow_deny       => $args->{"allow_deny"}{'value'},
        eval_position    => $args->{"eval_position"}{'value'},
        vlan_start       => $args->{"vlan_start"}{'value'},
        vlan_end         => $args->{"vlan_end"}{'value'} || undef,
        notes            => $args->{"notes"}{'value'} || undef,
        user_id          => $user_id
    );

    my $workgroup_id = $args->{'workgroup_id'}{'value'};
    my $workgroup_name;
    if ($workgroup_id){
        $workgroup_name = $db->get_workgroup_by_id(workgroup_id => $workgroup_id)->{'name'};
    }
    else{
        $workgroup_name = "All workgroups";
    }
    my $interface_name = $db->get_interface(interface_id => $args->{"interface_id"}{'value'})->{'name'}; 
    my $vlan_start = $args->{"vlan_start"}{'value'};
    my $vlan_end = $args->{"vlan_end"}{'value'};
    my $logger = Log::Log4perl->get_logger("OESS.ACL");
    
    if ( !defined $success ) {
        $logger->info("Failed to update acl with id $acl_id, at ". localtime() . " on $interface_name. Action was initiated by $username."); 
        $method->set_error( $db->get_error() );
	return;
    }

    else {
        #get the passed values
        my %passed_values = $args;
        my $passed_values_hash;
        foreach my $passed_value (keys %passed_values) {

            #we don't need the action param or notes
            if ($passed_value eq "action" || $passed_value eq "notes") {
                next;
            }
            $passed_values_hash->{$passed_value} = $args->{$passed_value}{'value'};
        }
        $logger->info("Updated ACL with id $acl_id, at ". localtime() ." on $interface_name. Action was initiated by $username.");
        
        #now compare and contrast values
        my $output_string = "Changed: ";  
        if( $original_values->{'vlan_start'} != $passed_values_hash->{'vlan_start'}) {
            $output_string .= "vlan start from " . $original_values->{'vlan_start'} . " to " . $passed_values_hash->{'vlan_start'};
        }

        if( $original_values->{'vlan_end'} != $passed_values_hash->{'vlan_end'}){
            $output_string .= " vlan end from " . $original_values->{'vlan_end'} . " to " . $passed_values_hash->{'vlan_end'};
        }  
        if( $original_values->{'allow_deny'} != $passed_values_hash->{'allow_deny'}) {
            $output_string .= " permission from " . $original_values->{'allow_deny'} . " to ". $passed_values_hash->{'allow_deny'}; 
        }

        if( $original_values->{'workgroup_id'} != $passed_values_hash->{'workgroup_id'}) {
            $output_string .= " workgroup from $original_workgroup_name to $workgroup_name. ";
        }

        $logger->info($output_string);
        $results->{'results'} = [ { success => 1 } ];
    }

    return $results;

}

sub remove_acl {

    my ( $method, $args ) = @_ ;
    my $results;
    my $logger = Log::Log4perl->get_logger("OESS.ACL");
 
    my $interface_acl_id   = $args->{'interface_acl_id'}{'value'};
    
    my $result = $db->remove_acl(
        user_id      => $user_id,
        interface_acl_id => $interface_acl_id
    );

    if ( !defined $result ) {
        $logger->info("Failed to delete ACL with id $interface_acl_id at ". localtime() ." Action was initiated by $username.");
	$method->set_error( $db->get_error() );
    }
    else {
        $logger->info("Deleted ACL with id $interface_acl_id at ". localtime() . " Action was initiated by $username.");
        $results->{'results'} = [ { success => 1 } ];
    }

    return $results;
}

sub parse_results {
    my %args = @_;

    my $res = $args{'res'};
    my $method = $args{'method'};
    my $results;
     
    if ( !defined $res ) {
        $method->set_error( $db->get_error() );
	return;
    }else {
        $results->{'results'} = $res;
    }

    return $results;
}

sub send_json {
    my $output = shift;
    if (!defined($output) || !$output) {
        $output =  { "error" => "Server error in accessing webservices." };
    }
    print "Content-type: text/plain\n\n" . encode_json($output);
}

main();

