#!/usr/bin/perl -T
#
##----- NDDI OESS provisioning.cgi
##-----                                                                                  
##----- $HeadURL: svn+ssh://svn.grnoc.iu.edu/grnoc/oe-ss/frontend/trunk/webservice/provisioning.cgi $
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----                                                                                
##----- Provides a WebAPI to allow for provisioning/decoming of circuits
##
##-------------------------------------------------------------------------
##
##                                                                                       
## Copyright 2011 Trustees of Indiana University                                         
##                                                                                       
##   Licensed under the Apache License, Version 2.0 (the "License");                     
##   you may not use this file except in compliance with the License.                     
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
use Net::DBus::Exporter qw(org.nddi.fwdctl);
use Data::Dumper;

use OESS::Database;

my $db   = new OESS::Database();

my $cgi  = new CGI;

$| = 1;

sub main {

    if (! $db){
	send_json({"error" => "Unable to connect to database."});
	exit(1);
    }    

    my $action = $cgi->param('action');

    my $output;

    switch ($action){
	
	case "provision_circuit" {
	    $output = &provision_circuit();
3	}
	case "remove_circuit" {
	    $output = &remove_circuit();
	}
	else{
	    $output = {error => "Unknown action - $action"};
	}

    }
    
    send_json($output);
    
}

sub _send_add_command {
    my %args = @_;

    my $bus = Net::DBus->system;

    my $client;
    my $service;

    eval {
	$service = $bus->get_service("org.nddi.fwdctl");
	$client  = $service->get_object("/controller1");
    };

    if ($@){
	warn "Error in _connect_to_fwdctl: $@";
	return undef;
    }
   

    if (! defined $client){
	return undef;
    }
    
    my $circuit_id = $args{'circuit_id'};

    my $result = $client->addVlan($circuit_id);

    warn "ADD RESULT: $result";

    return $result;
}

sub _send_remove_command {
    my %args = @_;

    my $bus = Net::DBus->system;

    my $client;
    my $service;
    
    eval {
	$service = $bus->get_service("org.nddi.fwdctl");
	$client  = $service->get_object("/controller1");
    };
    
    if ($@){
	warn "Error in _connect_to_fwdctl: $@";
	return undef;
    }
   

    if (! defined $client){
	return undef;
    }
    
    my $circuit_id = $args{'circuit_id'};

    my $result = $client->deleteVlan($circuit_id);

    warn "RESULT: " . Dumper($result);

    return $result;
}


sub provision_circuit {

    my $results;

    $results->{'results'} = [];

    my $output;

    my $workgroup_id = $cgi->param('workgroup_id');
    my $external_id  = $cgi->param('external_identifier');

    my $circuit_id   = $cgi->param('circuit_id');
    my $description  = $cgi->param('description');
    my $bandwidth    = $cgi->param('bandwidth');

    my $provision_time = $cgi->param('provision_time');
    my $remove_time    = $cgi->param('remove_time');

    my @links        = $cgi->param('link');
    my @backup_links = $cgi->param('backup_link');
    my @nodes        = $cgi->param('node');
    my @interfaces   = $cgi->param('interface');
    my @tags         = $cgi->param('tag');
    
    my @remote_nodes = $cgi->param('remote_node');
    my @remote_tags  = $cgi->param('remote_tag');

    if (!$circuit_id || $circuit_id eq -1){
	$output = $db->provision_circuit(description    => $description,
					 bandwidth      => $bandwidth,
					 provision_time => $provision_time,
					 remove_time    => $remove_time,
					 links          => \@links,
					 backup_links   => \@backup_links,
					 nodes          => \@nodes,
					 interfaces     => \@interfaces,
					 tags           => \@tags,
					 user_name      => $ENV{'REMOTE_USER'},
					 workgroup_id   => $workgroup_id,
					 external_id    => $external_id 
	                                );

	if (defined $output && $provision_time <= time()){

	    my $result = _send_add_command(circuit_id => $output->{'circuit_id'});
	
	    if (! defined $result){
		$output->{'warning'} = "Unable to talk to fwdctl service - is it running?";
	    }
	    
	    # failure, remove the circuit now
	    if ($result == 0){
		$cgi->param('circuit_id', $output->{'circuit_id'});
		$cgi->param('remove_time', -1);
		$cgi->param('force', 1);
		my $removal = remove_circuit();

		warn "Removal status: " . Data::Dumper::Dumper($removal);

		$results->{'error'} = "Unabled to provision circuit. Please check your logs or contact your server adminstrator for more information. Circuit has been removed.";
		return $results;
	    }

	}

    }
    else{

	my $result = _send_remove_command(circuit_id => $circuit_id);
	
	if (! $result){
	    $output->{'warning'} = "Unable to talk to fwdctl service - is it running?";
	    return;
	}

	if ($result == 0){
	    $results->{'error'} = "Unable to remove circuit. Please check your logs or contact your server adminstrator for more information. Circuit has been left in the database.";
	    return $results;
	}
        

	$output = $db->edit_circuit(circuit_id     => $circuit_id,
				    description    => $description,
				    bandwidth      => $bandwidth,
				    provision_time => $provision_time,
				    remove_time    => $remove_time,
				    links          => \@links,
				    backup_links   => \@backup_links,
				    nodes          => \@nodes,
				    interfaces     => \@interfaces,
				    tags           => \@tags,
				    user_name      => $ENV{'REMOTE_USER'},
				    workgroup_id   => $workgroup_id,
				    do_external    => 0
	                           );

	$result = _send_add_command(circuit_id => $output->{'circuit_id'});
	
	if (! defined $result){
	    $output->{'warning'} = "Unable to talk to fwdctl service - is it running?";
	}       

	if ($result == 0){
	    $results->{'error'} = "Unable to edit circuit. Please check your logs or contact your server adminstrator for more information. Circuit is likely not live on the network anymore.";
	    return $results;
	}


    }

    if (! defined $output){
	$results->{'error'}   = $db->get_error();
    }
    else{
	$results->{'results'} = $output;
    }

    return $results;
}

sub remove_circuit {
    my $results;

    my $circuit_id  = $cgi->param('circuit_id');
    my $remove_time = $cgi->param('remove_time'); 
    my $workgroup_id = $cgi->param('workgroup_id');
    $results->{'results'} = [];

    my $can_remove = $db->can_modify_circuit(circuit_id  => $circuit_id,
					     username   => $ENV{'REMOTE_USER'},
					     workgroup_id => $workgroup_id
	);
    
    if (! defined $can_remove){
        $results->{'error'}   = $db->get_error();
        return $results;
    }

    if($can_remove < 1){
	$results->{'error'} = "Users and workgroup do not have permission to remove this circuit";
	return $results;
    }

    # removing it now, otherwise we'll just schedule it for later
    if ($remove_time && $remove_time <= time()){
	my $result = _send_remove_command(circuit_id => $circuit_id);

	if (! defined $result){
	    $results->{'error'} = "Unable to talk to fwdctl service - is it running?";
	    return $results;
	}

	if ($result == 0){
	    $results->{'error'} = "Unable to remove circuit. Please check your logs or contact your server adminstrator for more information. Circuit has been left in the database.";

	    # if force is sent, it will clear it from the database regardless of whether fwdctl reported success or not
	    if (! $cgi->param('force')){
		return $results;
	    }
	}

    }

    my $output = $db->remove_circuit(circuit_id  => $circuit_id,
                                     remove_time => $remove_time,
				     user_name   => $ENV{'REMOTE_USER'},
                                     workgroup_id => $workgroup_id
	);

    if (! defined $output){
        $results->{'error'}   = $db->get_error();
        return $results;
    }

    $results->{'results'} = [{success => 1}];
    
    return $results;
}

sub send_json{
    my $output = shift;

    print "Content-type: text/plain\n\n" . encode_json($output);
}

main();

