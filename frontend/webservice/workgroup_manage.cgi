#!/usr/bin/perl
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

use OESS::DB;
use OESS::DB::Interface;
use OESS::DB::ACL;
use OESS::DB::User;

use GRNOC::WebService;
use OESS::Webservice;
use OESS::AccessController::Default;

use OESS::ACL;

Log::Log4perl::init_and_watch('/etc/oess/logging.conf');

my $db   = new OESS::DB();

#register web service dispatcher
my $svc = GRNOC::WebService::Dispatcher->new(method_selector => ['method', 'action']);

my $username = $ENV{'REMOTE_USER'};
my $user_id;

$| = 1;

sub main {
    #register the WebService Methods
    register_webservice_methods();

    #handle the WebService request.
    $svc->handle_request();

}

sub register_webservice_methods {

    my $method;

    #ESS
    #get_all_workgroups()
     $method = GRNOC::WebService::Method->new(
	 name            => "get_all_workgroups",
	 description     => "returns a list of workgroups the logged in user has access to",
	 callback        => sub { get_all_workgroups( @_ ) },
     method_deprecated => "This method has been deprecated in favor of user.cgi?method=get_current."
	 );

    #register get_workgroups() method
    $svc->register_method($method);

    #get_acls
    $method = GRNOC::WebService::Method->new(
	name            => "get_acls",
	description     => "Returns a JSON formatted list of ACLs for a given interface.",
	callback        => sub { get_acls( @_ ) },
    method_deprecated => "This method has been deprecated in favor of acl.cgi?method=get_acls."
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
	callback        => sub { add_acl( @_ ) },
    method_deprecated => "This method has been deprecated in favor of acl.cgi?method=create_acl."
	);

    #add the optional input parameter workgroup_id
    $method->add_input_parameter(
	name            => 'workgroup_id',
	pattern         => $GRNOC::WebService::Regex::INTEGER,
	required        => 0,
	description     => "the workgroup the ACL is applied to."
	); 

    $method->add_input_parameter(
        name            => 'entity_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "Specific entity_id add the ACL to"
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
        pattern         => $OESS::Webservice::ACL_ALLOW_DENY,
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
        callback        => sub { update_acl( @_ ) },
        method_deprecated => "This method has been deprecated in favor of acl.cgi?method=edit_acl."
        );

    #add the optional input parameter workgroup_id
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "the workgroup the ACL is applied to."
        );
    $method->add_input_parameter(
        name            => 'entity_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "the entity the ACL is applied to."
        );

    #add the required input parameter interface_id
    $method->add_input_parameter(
        name            => 'interface_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "Unused; kept for backwards compatibility"
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
        pattern         => $OESS::Webservice::ACL_ALLOW_DENY,
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
        name            => 'start',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "the start vlan tag."
        );

    #add the optional input paramter vlan_end
    $method->add_input_parameter(
        name            => 'end',
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
	callback        => sub { remove_acl( @_ ) },
    method_deprecated => "This method has been deprecated in favor of acl.cgi?method=delete_acl."
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
    
    if (!defined $db) {
        $method->set_error("Error connecting to Database");
        return;
    }

    my ($workgroups, $error) = OESS::DB::Workgroup::fetch_all(db => $db);
    if (defined $error) {
        $method->set_error($error);
        return;
    }

    return { results => $workgroups};
}

sub get_acls {
    
    my ( $method, $args ) = @_ ;
    my $results;

    my $acls;
    if($args->{'interface_id'}{'value'}){
        my $request_interface = OESS::DB::Interface::fetch(db => $db, interface_id => $args->{'interface_id'}{'value'});
        if (!defined $request_interface) {
            $method->set_error('Error getting ACLs. ' . $db->get_error);
            return;
        }
        my $request_workgroup = $request_interface->{workgroup_id};
        my ($permission, $err) = OESS::DB::User::has_workgroup_access(
                                    db => $db,
                                    username => $username,
                                    workgroup_id => $request_workgroup,
                                    role => 'read-only'
                                );
        if (defined $err) {
            $method->set_error($err);
            return;
        }

        $acls = OESS::DB::ACL::fetch_all(db => $db, interface_id => $args->{'interface_id'}{'value'});
    }
    if($args->{'interface_acl_id'}{'value'}){
        $acls->[0] = OESS::DB::ACL::fetch(db => $db, interface_acl_id => $args->{'interface_acl_id'}{'value'});
        my $request_workgroup = OESS::DB::Interface::fetch(db => $db, interface_id => $acls->[0]->{interface_id})->{workgroup_id};
        my ($permission, $err) = OESS::DB::User::has_workgroup_access(
                                    db => $db,
                                    username => $username,
                                    workgroup_id => $request_workgroup,
                                    role => 'read-only'
                                );
        if (defined $err) {
            $method->set_error($err);
            return;
        }
        
    }
    if (!defined $acls){
        my $error = $db->get_error();
        $method->set_error($error);
        return;
    }

    return { results => $acls};
}

sub add_acl {
    
    my ( $method, $args ) = @_ ;
    my $results;
    
    if (!defined $db) {
        $method->set_error("Error Connecting to Database");
        return;
    }

    my $workgroup_id = $args->{'workgroup_id'}{'value'} || undef;
    my $workgroup_name;
    if (!defined $workgroup_id){
        $workgroup_name = "all workgroups";
    } else {
        $workgroup_name = OESS::DB::Workgroup::fetch(db => $db, workgroup_id => $workgroup_id)->{'name'};
    }

    my $interface = OESS::DB::Interface::fetch(db => $db, interface_id => $args->{"interface_id"}{'value'});
    my ($permissions, $err) = OESS::DB::User::has_workgroup_access(
                                db => $db,
                                username => $username,
                                workgroup_id => $interface->{workgroup_id},
                                role => 'normal'
                            );
    if (defined $err) {
        $method-> set_error($err);
        return;
    }
    my $ac = new OESS::AccessController::Default(db => $db);
    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    my $interface_name = $interface->{name};
    my $vlan_start = $args->{"vlan_start"}{'value'};
    my $vlan_end = $args->{"vlan_end"}{'value'};
    my $logger = Log::Log4perl->get_logger("OESS.ACL");
    $logger->debug("Initiating creation of ACL at <time> for ");    
    my $acl_model = { 
        workgroup_id  => $args->{"workgroup_id"}{'value'} || undef,
        interface_id  => $args->{"interface_id"}{'value'},
        allow_deny    => $args->{"allow_deny"}{'value'},
        eval_position => $args->{"eval_position"}{'value'} || undef,
        start    => $args->{"vlan_start"}{'value'},
        end      => $args->{"vlan_end"}{'value'} || undef,
        notes         => $args->{"notes"}{'value'} || undef,
        entity_id     => $args->{"entity_id"}{'value'} || undef,
        user_id       => $user->user_id
    };
    my ($acl_id, $acl_error) = OESS::DB::ACL::create(db => $db, model => $acl_model);
    if ( defined $acl_error ) {
        $logger->error("Error creating ACL at ". localtime(). " for $workgroup_name, on $interface_name from vlans $vlan_start to $vlan_end. Action was initiated by $username");
	$method->set_error( $acl_error );
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
    my ($method, $args) = @_ ;

    my $acl_id       = $args->{interface_acl_id}{value};
    my $workgroup_id = $args->{workgroup_id}{value};
    my $vlan_start   = $args->{start}{value};
    my $vlan_end     = $args->{end}{value};
    my $logger       = Log::Log4perl->get_logger("OESS.ACL");

    if (!defined $db) {
        $method->set_error("Error connecting to Database");
        return;
    }
    my $request_interface = OESS::DB::ACL::fetch(db => $db, interface_acl_id => $acl_id)->{interface_id};
    my $request_workgroup = OESS::DB::Interface::fetch(db => $db, interface_id => $request_interface)->{workgroup_id};
    my ($permissions, $err) = OESS::DB::User::has_workgroup_access(
                                db => $db,
                                username => $username,
                                workgroup_id => $request_workgroup,
                                role => 'normal'
                            );
    if (defined $err) {
        $method-> set_error($err);
        return;
    }

    my $original_acl = OESS::ACL->new(db => $db, interface_acl_id => $acl_id);
    my $acl = OESS::ACL->new(db => $db, interface_acl_id => $acl_id);
    $db->start_transaction();
    if($acl->{'eval_position'} != $args->{eval_position}{value}){
        #doing an interface move... grab all the acls for this interface
        my $interface = OESS::Interface->new( db => $db, interface_id => $acl->{interface_id});

        foreach my $a (@{$interface->acls()}){
	    next if $a->{acl_id} == $acl_id;
	    
	    if($args->{eval_position}{value} < $acl->{eval_position}){
		
		if($a->{eval_position} >= $args->{eval_position}{value} && $a->{eval_position} < $acl->{eval_position}){
		    $a->{eval_position} += 10;
		    if(!$a->update_db()){
			$method->set_error( $db->get_error() );
			$db->rollback();
			return;
		    }
		}

	    }elsif( $args->{eval_position}{value} > $acl->{eval_position}){
		if($a->{eval_position} <= $args->{eval_position}{value} && $a->{eval_position} > $acl->{eval_position}){
		    $a->{eval_position} -= 10;
		    if(!$a->update_db()){
			$method->set_error( $db->get_error() );
                        $db->rollback();
                        return;
		    }
		}
	    }
	}
    }

    $acl->{workgroup_id}  = $args->{workgroup_id}{value};
    $acl->{interface_id}  = $args->{interface_id}{value};
    $acl->{entity_id}     = $args->{entity_id}{value};
    $acl->{allow_deny}    = $args->{allow_deny}{value};
    $acl->{eval_position} = $args->{eval_position}{value};
    $acl->{start}         = $args->{start}{value};
    $acl->{end}           = $args->{end}{value};
    $acl->{notes}         = $args->{notes}{value};
    my $success = $acl->update_db();

    my $original_values =  $original_acl->to_hash();

    my $original_workgroup_name;
    if ($original_acl->{workgroup_id}) {
        $original_workgroup_name = OESS::DB::Workgroup::fetch(db => $db, workgroup_id => $original_acl->{workgroup_id})->{name};
    } else{
        $original_workgroup_name = "All workgroups";
    }

    my $workgroup_name;
    if ($workgroup_id && $workgroup_id != -1){
        $workgroup_name = OESS::DB::Workgroup::fetch(db => $db, workgroup_id => $acl->{workgroup_id})->{'name'};
    } else{
        $workgroup_name = "All workgroups";
    }

    my $original_interface_name = OESS::DB::Interface::fetch(db => $db, interface_id => $original_acl->{interface_id})->{name};
    my $interface_name = OESS::DB::Interface::fetch(db => $db, interface_id => $acl->{interface_id})->{'name'};

    if (!defined $success) {
        $logger->info("Failed to update acl with id $acl_id, at ". localtime() . " on $interface_name. Action was initiated by $username.");
        $method->set_error( $db->get_error() );
	$db->rollback();
        return;
    }

    $db->commit();

    my $output_string = "Changed: ";
    if ($original_acl->{start} != $acl->{start}) {
        $output_string .= "vlan start from $original_acl->{start} to $acl->{start}";
    }
    if ($original_acl->{end} != $acl->{end}) {
        $output_string .= " vlan end from $original_acl->{end} to $acl->{end}";
    }
    if ($original_acl->{allow_deny} ne $acl->{allow_deny}) {
        $output_string .= " permission from $original_acl->{allow_deny} to $acl->{allow_deny}";
    }
    if ($original_acl->{workgroup_id} != $acl->{workgroup_id}) {
        $output_string .= " workgroup from $original_acl->{workgroup_id} to $acl->{workgroup_id}";
    }

    $logger->info("Updated ACL with id $acl_id, at ". localtime() ." on $interface_name. Action was initiated by $username.");
    $logger->info($output_string);

    return { results => [{ success => 1 }] };

}

sub remove_acl {

    my ( $method, $args ) = @_ ;
    my $results;
    my $logger = Log::Log4perl->get_logger("OESS.ACL");

    if (!defined $db) {
        $method->set_error("Error connecting to the Database");
        return;
    }
    my $interface_acl_id   = $args->{'interface_acl_id'}{'value'};
    my $request_interface = OESS::DB::ACL::fetch(db => $db, interface_acl_id => $interface_acl_id)->{interface_id};
    my $request_workgroup = OESS::DB::Interface::fetch(db => $db, interface_id => $request_interface)->{workgroup_id};
    my ($permissions, $err) = OESS::DB::User::has_workgroup_access(
                                db => $db,
                                username => $username,
                                workgroup_id => $request_workgroup,
                                role => 'normal'
                            );
    if (defined $err) {
        $method-> set_error($err);
        return;
    }

    my ($result,$error) = $db->execute_query("select interface_id, workgroup_id from interface_acl where interface_acl_id = $interface_acl_id");

    my ($result,$error) = OESS::DB::ACL::remove(
        db => $db,
        interface_acl_id => $interface_acl_id,
        interface_id => $request_interface,
        workgroup_id => $result->[0]->{workgroup_id}
    );

    if ( defined $error ) {
        $logger->info("Failed to delete ACL with id $interface_acl_id at ". localtime() ." Action was initiated by $username.");
	    $method->set_error( $error );
        return;
    }
    else {
        $logger->info("Deleted ACL with id $interface_acl_id at ". localtime() . " Action was initiated by $username.");
        $results->{'results'} = [ { success => 1 } ];
    }

    return $results;
}

main();

