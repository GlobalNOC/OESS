#!/usr/bin/perl

#------ OESS MPLS Discovery Module
##-----
##----- Provides object oriented methods to interact with the OESS Database
##-------------------------------------------------------------------------
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

=head1 NAME
OESS::MPLS::Discovery - OESS MPLS (traditional networking based) Discovery sub-component

This module is the orchestrator for the topology and path detection capabilities in the MPLS
version of OESS.  This is the class called by app/mpls/mpls_discovery.pl and handles 
interaction with the devices to fetch the required information for the sub-components of
the OESS::MPLS::Discovery module.  Essentially this module is the scheduler and data
wrangler for the other modules.  It should be straight forward to add additional functionality
including different protcols to this.

=cut

use strict;
use warnings;

package OESS::MPLS::Discovery;

use AnyEvent::Fork;
use Data::Dumper;
use Socket;
use GRNOC::RabbitMQ::Client;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Dispatcher;
use OESS::RabbitMQ::Client;
use OESS::RabbitMQ::Dispatcher;
use GRNOC::WebService::Regex;
use OESS::Database;

use OESS::MPLS::Discovery::Interface;
use OESS::MPLS::Discovery::LSP;
use OESS::MPLS::Discovery::ISIS;
use OESS::MPLS::Discovery::Paths;

use Log::Log4perl;

use AnyEvent;

=head2 new
    instantiates a new OESS::MPLS::Discovery object, which intern creates new 
    instantiations of 

    OESS::MPLS::Discovery::Interface
    OESS::MPLS::Discovery::LSP
    OESS::MPLS::Discovery::ISIS
    
    this then schedules timed events to handle our data requests and processing
    from the other modules.  This module also will handle new device additions
    and initial device population

=cut

sub new{
    my $class = shift;
    #process our args
    my %args = (
        @_
        );

    my $self = \%args;

    #setup the logger
    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.Discovery');
    bless $self, $class;

    #create the DB
    if(!defined($self->{'config'})){
        $self->{'config'} = "/etc/oess/database.xml";
    }
    $self->{'db'} = OESS::Database->new( config_file => $self->{'config'} );

    die if(!defined($self->{'db'}));

    #init our sub modules
    $self->{'interface'} = $self->_init_interfaces();
    die if (!defined($self->{'interface'}));
    $self->{'lsp'} = $self->_init_lsp();
    die if (!defined($self->{'lsp'}));
    $self->{'isis'} = $self->_init_isis();
    die if (!defined($self->{'isis'}));
    $self->{'path'} = $self->_init_paths();
    die if (!defined($self->{'path'}));
    

    #create the client for talking to our Discovery switch objects!
    $self->{'rmq_client'} = OESS::RabbitMQ::Client->new( timeout => 15,
							 topic => 'MPLS.Discovery');
    
    die if(!defined($self->{'rmq_client'}));

    #setup the timers
    $self->{'device_timer'} = AnyEvent->timer( after => 10, interval => 60, cb => sub { $self->device_handler(); });
    $self->{'int_timer'} = AnyEvent->timer( after => 20, interval => 60, cb => sub { $self->int_handler(); });
    $self->{'lsp_timer'} = AnyEvent->timer( after => 30, interval => 60, cb => sub { $self->lsp_handler(); });
    $self->{'isis_timer'} = AnyEvent->timer( after => 40, interval => 60, cb => sub { $self->isis_handler(); } );
    $self->{'path_timer'} = AnyEvent->timer( after => 50, interval => 60, cb => sub { $self->path_handler(); });

    #our dispatcher for receiving events (only new_switch right now)    
    my $dispatcher = OESS::RabbitMQ::Dispatcher->new( queue => 'MPLS-Discovery',
						      topic => "MPLS.Discovery.RPC");

    $self->register_rpc_methods( $dispatcher );
    $self->{'dispatcher'} = $dispatcher;

    # When this process receives sigterm send an event to notify all
    # children to exit cleanly.
    $SIG{TERM} = sub {
        $self->stop();
    };

    #create a child process for each switch
    my $nodes = $self->{'db'}->get_current_nodes( mpls => 1);
    foreach my $node (@$nodes) {
	warn "Making Baby!\n";
	$self->make_baby($node->{'node_id'});
    }

    return $self;
}

=head2 register_rpc_methods

this sets up our dispatcher to receive remote events

=cut

sub register_rpc_methods{
    my $self = shift;
    my $d = shift;
    my $method = GRNOC::RabbitMQ::Method->new( name => "new_switch",
                                               async => 1,
					       callback => sub { $self->new_switch(@_) },
					       description => "adds a new switch to the DB and starts a child process to fetch its details");
    
    $method->add_input_parameter( name => "node_id",
                                  description => "the node_id of the new node",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NUMBER_ID);

    $d->register_method($method);
}

=head2 new_switch

this is called when a new switch is added to the network... the job
of this module is to add the device and its interfaces (and links) 
to the OESS database for future provisioning use

=cut

sub new_switch{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    my $state_ref = shift;

    my $success = $m_ref->{'success_callback'};
    my $error   = $m_ref->{'error_callback'};

    my $node_id = $p_ref->{'node_id'}{'value'};

    #sherpa will you make my babies!
    $self->make_baby($node_id);
    $self->{'logger'}->debug("Baby was created!");
    sleep(5);
    $self->int_handler();
    $self->lsp_handler();

    &$success({status => 1});
}


=head2 make_baby
make baby is a throw back to sherpa...
have to give Ed the credit for most
awesome function name ever

really this creates a switch object that can
handle our RabbitMQ requests and returns results
from the device

=cut
sub make_baby{
    my $self = shift;
    my $id = shift;

    $self->{'logger'}->debug("Before the fork");

    my $node = $self->{'db'}->get_node_by_id(node_id => $id);

    my %args;
    $args{'id'} = $id;
    $args{'rabbitMQ_host'} = $self->{'db'}->{'rabbitMQ'}->{'host'};
    $args{'rabbitMQ_port'} = $self->{'db'}->{'rabbitMQ'}->{'port'};
    $args{'rabbitMQ_user'} = $self->{'db'}->{'rabbitMQ'}->{'user'};
    $args{'rabbitMQ_pass'} = $self->{'db'}->{'rabbitMQ'}->{'pass'};
    $args{'rabbitMQ_vhost'} = $self->{'db'}->{'rabbitMQ'}->{'vhost'};
    $args{'vendor'} = $node->{'vendor'};
    $args{'model'} = $node->{'model'};
    $args{'sw_version'} = $node->{'sw_version'};
    $args{'mgmt_addr'} = $node->{'mgmt_addr'};
    $args{'name'} = $node->{'name'};
    $args{'use_cache'} = 0;
    $args{'topic'} = "MPLS.Discovery.Switch";
    my $proc = AnyEvent::Fork->new->require("Log::Log4perl", "OESS::MPLS::Switch")->eval('
use strict;
use warnings;
use Data::Dumper;
my $switch;
my $logger;

Log::Log4perl::init_and_watch("/etc/oess/logging.conf",10);
sub run{
    my $fh = shift;
    my %args = @_;
    $logger = Log::Log4perl->get_logger("MPLS.Discovery.MASTER");
    $logger->info("Creating child for id: " . $args{"id"});
    $args{"node"} = {"vendor" => $args{"vendor"}, "model" => $args{"model"}, "sw_version" => $args{"sw_version"}, "name" => $args{"name"}, "mgmt_addr" => $args{"mgmt_addr"}};			  
    $switch = OESS::MPLS::Switch->new( %args );
}')->fork->send_arg( %args )->run("run");

    $self->{'children'}->{$id} = {};
    $self->{'children'}->{$id}->{'rpc'} = 1;
}

#initialize our sub modules...
sub _init_interfaces{
    my $self = shift;
    
    my $ints = OESS::MPLS::Discovery::Interface->new( db => $self->{'db'},
						      lsp_processor => sub{ $self->lsp_handler(); } );
    if(!defined($ints)){
	die "Unable to create Interface processor\n";
    }

    return $ints;
}

sub _init_lsp{
    my $self = shift;

    my $lsps = OESS::MPLS::Discovery::LSP->new( db => $self->{'db'});
    if(!defined($lsps)){
	die "Unable to create LSP Processor\n";
    }

    return $lsps;

}

sub _init_isis{  
    my $self = shift;

    my $isis = OESS::MPLS::Discovery::ISIS->new( db => $self->{'db'} );
    if(!defined($isis)){
	die "Unable to create ISIS Processor\n";
    }

    return $isis;

}

sub _init_paths{
    my $self = shift;
    my $paths = OESS::MPLS::Discovery::Paths->new( db => $self->{'db'} );
    if(!defined($paths)){
        die "Unable to create Path Processor\n";
    }

    return $paths;
}

=head2 int_handler

=cut
sub int_handler{
    my $self = shift;
    
    foreach my $node (@{$self->{'db'}->get_current_nodes(mpls => 1)}){
	$self->{'rmq_client'}->{'topic'} = "MPLS.Discovery.Switch." . $node->{'mgmt_addr'};
	$self->{'rmq_client'}->get_interfaces( async => 1,
					       async_callback => $self->handle_response( cb => sub { my $res = shift;
                                                                                                     $self->{'db'}->update_node_operational_state(node_id => $node->{'node_id'}, state => 'up', protocol => 'mpls');
                                                                                                     my $status = $self->{'interface'}->process_results( node => $node->{'name'}, interfaces => $res->{'results'});
											 }));
    }
}

=head2 path_handler

=cut

sub path_handler {

    my $self = shift;

    warn "IN Path handler\n";

    $self->{'logger'}->info("path_handler: calling");

    my $nodes = $self->{'db'}->get_current_nodes( mpls => 1 );
    if (!defined $nodes) {
        $self->{'logger'}->error("path_handler: Could not get current nodes.");
        return 0;
    }

    my @loopback_addrs;

    foreach my $node (@{$nodes}) {
        if (!defined $node->{'loopback_address'}) {
            next;
        }
        push(@loopback_addrs, $node->{'loopback_address'});
    }
    
    foreach my $node (@{$nodes}){ 
        $self->{'rmq_client'}->{'topic'} = "MPLS.Discovery.Switch." . $node->{'mgmt_addr'};
        $self->{'rmq_client'}->get_default_paths( loopback_addresses => \@loopback_addrs,
                                                  async_callback     => sub {
                                                      my $res = shift;
                                                      warn "Processing results\n";
                                                      $self->{'path'}->process_results( paths => $res->{'results'}, node_id => $node->{'node_id'} );
                                                      return 1;
                                                  } );
    }
}

=head2 lsp_handler

=cut

sub lsp_handler{
    my $self = shift;
    
    my %nodes;

    foreach my $node (@{$self->{'db'}->get_current_nodes(mpls => 1)}){
	$nodes{$node->{'name'}} = {'pending' => 1};
	$self->{'rmq_client'}->{'topic'} = "MPLS.Discovery.Switch." . $node->{'mgmt_addr'};
        $self->{'rmq_client'}->get_LSPs( async => 1,
					 async_callback => $self->handle_response( cb => sub { my $res = shift;
											       $nodes{$node->{'name'}} = $res;
											       $nodes{$node->{'name'}}->{'pending'} = 0;
											       my $no_pending = 1;
											       foreach my $node (keys %nodes){
												   if($nodes{$node}->{'pending'} == 1){
												       #warn "Still have pending\n";
												       $no_pending = 0;
												   }
											       }

											       if($no_pending){
												   #warn "No more pending\n";
												   my $status = $self->{'lsp'}->process_results( lsp => \%nodes);
											       }
										   })
					 
            );
    }
}

=head2 isis_handler

=cut

sub isis_handler{
    my $self = shift;


    my %nodes;
    foreach my $node (@{$self->{'db'}->get_current_nodes(mpls => 1)}){
	$nodes{$node->{'short_name'}} = {'pending' => 1};
        $self->{'rmq_client'}->{'topic'} = "MPLS.Discovery.Switch." . $node->{'mgmt_addr'};
        $self->{'rmq_client'}->get_isis_adjacencies( async => 1,
                                        async_callback => $self->handle_response( cb => sub { my $res = shift;
											      $nodes{$node->{'short_name'}} = $res;
											      $nodes{$node->{'short_name'}}->{'pending'} = 0;
											      my $no_pending = 1;
											      foreach my $node (keys %nodes){
												  if($nodes{$node}->{'pending'} == 1){
												      $no_pending = 0;
												  }
											      }
											      
											      if($no_pending){
												  warn "ISIS: No more pending\n";
												  my $adj = $self->{'isis'}->process_results( isis => \%nodes);
												  $self->handle_links($adj);
											      }
                                                                                  })
					
            );
    }
}

=head2 device_handler

=cut

sub device_handler{
    my $self =shift;
    foreach my $node (@{$self->{'db'}->get_current_nodes(mpls => 1)}){
        $self->{'rmq_client'}->{'topic'} = "MPLS.Discovery.Switch." . $node->{'mgmt_addr'};
        $self->{'rmq_client'}->get_system_info( async => 1,
						async_callback => $self->handle_response( cb => sub {
                                                                                              my $res = shift;
                                                                                              if (defined $res->{'error'}) {
                                                                                                  my $addr = $node->{'mgmt_addr'};
                                                                                                  my $err = $res->{'error'};
                                                                                                  $self->{'logger'}->error("Error calling get_system_info on $addr: $err");
                                                                                                  return;
                                                                                              }

                                                                                              $self->handle_system_info(node => $node->{'node_id'}, info => $res->{'results'});
											  }));
    }
    
}

=head2 handle_system_info

=cut

sub handle_system_info{
    my $self = shift;
    my %params = @_;
    
    my $node = $params{'node'};
    my $info = $params{'info'};

    my $query = "update node_instantiation set loopback_address = ? where node_id = ?";
    $self->{'db'}->_execute_query($query,[$info->{'loopback_addr'},$node]);

}

=head2 handle_links

=cut

sub handle_links{
    my $self = shift;
    my $adj = shift;

    my %node_info;
    my $nodes = $self->{'db'}->get_current_nodes( mpls => 1);

    #build a Node hash by name...
    foreach my $node (@$nodes) {
        my $details = $self->{'db'}->get_node_by_id(node_id => $node->{'node_id'});
        next if(!$details->{'mpls'});
        $details->{'node_id'} = $details->{'node_id'};
        $details->{'id'} = $details->{'node_id'};
        $details->{'name'} = $details->{'name'};
        $details->{'ip'} = $details->{'ip'};
        $details->{'vendor'} = $details->{'vendor'};
        $details->{'model'} = $details->{'model'};
        $details->{'sw_version'} = $details->{'sw_version'};
        $node_info{$node->{'name'}} = $details;
	$node_info{$details->{'short_name'}} = $details;
    }

    #warn Dumper($adj);

    $self->{'db'}->_start_transaction();

    foreach my $node_a (keys (%{$adj})){
        foreach my $node_z (keys(%{$adj->{$node_a}})){

            if (!defined($adj->{$node_a}{$node_z}{'node_z'}{'interface_name'}) || !defined($adj->{$node_a}{$node_z}{'node_a'}{'interface_name'})) {
                $self->{'logger'}->info("Link Instantiation: Couldn't find a required endpoint name:A-Z: " . Data::Dumper::Dumper($adj->{$node_a}{$node_z}));
                $self->{'logger'}->info("Link Instantiation: Couldn't find a required endpoint name:Z-A: " . Data::Dumper::Dumper($adj->{$node_z}{$node_a}));
                next;
            }
	    
	    my $actual_node_a = $node_info{$node_a}->{'name'};
	    my $actual_node_z = $node_info{$node_z}->{'name'};

	    my $a_int = $self->{'db'}->get_interface_id_by_names( node => $actual_node_a,
	        						  interface => $adj->{$node_a}{$node_z}{'node_a'}{'interface_name'});
	    my $z_int = $self->{'db'}->get_interface_id_by_names( node => $actual_node_z,
	        						  interface => $adj->{$node_a}{$node_z}{'node_z'}{'interface_name'});
	    
	    if (!defined($a_int) || !defined($z_int)) {
                $self->{'logger'}->info("Link Instantiation: Couldn't find interface_ids.");
                next;
            }

	    #find current link if any
	    my ($link_db_id, $link_db_state) = $self->get_active_link_id_by_connectors( interface_a_id => $a_int, interface_z_id => $z_int);
	    
	    if($link_db_id){
				
		#$self->{'db'}->update_link_state( link_id => $link_db_id, state => 'up');
	    }else{
		#first determine if any of the ports are currently used by another link... and connect to the same other node
		my $links_a = $self->{'db'}->get_link_by_interface_id( interface_id => $a_int, show_decom => 0);
		my $links_z = $self->{'db'}->get_link_by_interface_id( interface_id => $z_int, show_decom => 0);
		
		my $z_node = $self->{'db'}->get_node_by_id( node_id => $node_info{$node_a}->{'node_id'});
		my $a_node = $self->{'db'}->get_node_by_id( node_id => $node_info{$node_z}->{'node_id'});
		
		my $a_links;
		my $z_links;
		
		#lets first remove any circuits not going to the node we want on these interfaces
		foreach my $link (@$links_a){
		    my $other_int = $self->{'db'}->get_interface( interface_id => $link->{'interface_a_id'} );
		    if($other_int->{'interface_id'} == $a_int){
			$other_int = $self->{'db'}->get_interface( interface_id => $link->{'interface_z_id'} );
		    }
		    
		    my $other_node = $self->{'db'}->get_node_by_id( node_id => $other_int->{'node_id'} );
		    if($other_node->{'node_id'} == $z_node->{'node_id'}){
			push(@$a_links,$link);
		    }
		}
		
		foreach my $link (@$links_z){
		    my $other_int = $self->{'db'}->get_interface( interface_id => $link->{'interface_a_id'} );
		    if($other_int->{'interface_id'} == $z_int){
			$other_int = $self->{'db'}->get_interface( interface_id => $link->{'interface_z_id'} );
		    }
		    my $other_node = $self->{'db'}->get_node_by_id( node_id => $other_int->{'node_id'} );
		    if($other_node->{'node_id'} == $a_node->{'node_id'}){
			push(@$z_links,$link);
		    }
		}
		

		#ok... so we now only have the links going from a to z nodes
		# we pretty much have 4 cases... there are 2 or more links going from a to z
		# there is 1 link going from a to z (this is enumerated as 2 elsifs one for each side)
		# there is no link going from a to z
		if(defined($a_links->[0]) && defined($z_links->[0])){
		    #ok this is the more complex one to worry about
		    #pick one and move it, we will have to move another one later
		    my $link = $a_links->[0];
		    my $old_z = $link->{'interface_a_id'};
		    if($old_z == $a_int){
			$old_z = $link->{'interface_z_id'};
		    }

		    my $old_z_interface = $self->{'db'}->get_interface( interface_id => $old_z);
		    $self->{'db'}->decom_link_instantiation( link_id => $link->{'link_id'} );
		    $self->{'db'}->create_link_instantiation( link_id => $link->{'link_id'}, interface_a_id => $a_int, interface_z_id => $z_int, state => $link->{'state'}, mpls => 1, ip_a => $adj->{$node_a}{$node_z}{'node_a'}{'ip_address'}, ip_z => $adj->{$node_a}{$node_z}{'node_z'}{'ip_address'} );
		}elsif(defined($a_links->[0])){
		    $self->{'logger'}->info("Link updated on the Z Side");

		    #easy case update link_a so that it is now on the new interfaces
		    my $link = $a_links->[0];
		    my $old_z = $link->{'interface_a_id'};
		    if($old_z == $a_int){
			$old_z = $link->{'interface_z_id'};
		    }
		    my $old_z_interface= $self->{'db'}->get_interface( interface_id => $old_z);
		    #if its in the links_a that means the z end changed...
		    $self->{'db'}->decom_link_instantiation( link_id => $link->{'link_id'} );
		    $self->{'db'}->create_link_instantiation( link_id => $link->{'link_id'}, interface_a_id => $a_int, interface_z_id => $z_int, state => $link->{'state'}, mpls => 1, ip_a => $adj->{$node_a}{$node_z}{'node_a'}{'ip_address'}, ip_z => $adj->{$node_a}{$node_z}{'node_z'}{'ip_address'} );
		}elsif(defined($z_links->[0])){
		    #easy case update link_a so that it is now on the new interfaces
		    my $link = $z_links->[0];

		    my $old_a = $link->{'interface_a_id'};
		    if($old_a == $z_int){
			$old_a = $link->{'interface_z_id'};
		    }
		    my $old_a_interface= $self->{'db'}->get_interface( interface_id => $old_a);
		    
		    $self->{'db'}->decom_link_instantiation( link_id => $link->{'link_id'});
		    $self->{'db'}->create_link_instantiation( link_id => $link->{'link_id'}, interface_a_id => $a_int, interface_z_id => $z_int, state => $link->{'state'}, mpls => 1, ip_a => $adj->{$node_a}{$node_z}{'node_a'}{'ip_address'}, ip_z => $adj->{$node_a}{$node_z}{'node_z'}{'ip_address'});
		}else{
		    my $link_name = $node_a . "-" . $adj->{$node_a}{$node_z}{'node_a'}{'interface_name'} . "--" . $node_z . "-" . $adj->{$node_a}{$node_z}{'node_z'}{'interface_name'};
		    my $link = $self->{'db'}->get_link_by_name(name => $link_name);
		    my $link_id;

		    if(!defined($link)){
			$link_id = $self->{'db'}->add_link( name => $link_name );
		    }else{
			$link_id = $link->{'link_id'};
		    }

		    if(!defined($link_id)){
			$self->{'db'}->_rollback();
			return undef;
		    }

		    $self->{'db'}->create_link_instantiation( link_id => $link_id, state => 'available', interface_a_id => $a_int, interface_z_id => $z_int, mpls => 1, ip_a => $adj->{$node_a}{$node_z}{'node_a'}{'ip_address'}, ip_z => $adj->{$node_a}{$node_z}{'node_z'}{'ip_address'});
		}
	    }
	}
    }
    $self->{'db'}->_commit();
}

=head2 get_active_link_id_by_connectors

=cut

sub get_active_link_id_by_connectors{
    my $self = shift;
    my %args = @_;
    
    my $a_dpid  = $args{'a_dpid'};
    my $a_port  = $args{'a_port'};
    my $z_dpid  = $args{'z_dpid'};
    my $z_port  = $args{'z_port'};
    my $interface_a_id = $args{'interface_a_id'};
    my $interface_z_id = $args{'interface_z_id'};

    if(defined $interface_a_id){

    }else{
        $interface_a_id = $self->{'db'}->get_interface_by_dpid_and_port( dpid => $a_dpid, port_number => $a_port);
    }

    if(defined $interface_z_id){

    }else{
        $interface_z_id = $self->{'db'}->get_interface_by_dpid_and_port( dpid => $z_dpid, port_number => $z_port);
    }

    #find current link if any
    my $link = $self->{'db'}->get_link_by_a_or_z_end( interface_a_id => $interface_a_id, interface_z_id => $interface_z_id);
    print STDERR "Found LInk: " . Data::Dumper::Dumper($link);
    if(defined($link) && defined(@{$link})){
        $link = @{$link}[0];
        print STDERR "Returning LinkID: " . $link->{'link_id'} . "\n";
        return ($link->{'link_id'}, $link->{'link_state'});
    }

    return undef;
}


=head2 handle_response

    this returns a callback for when we get our sync data reply
    it looks complicated but really it takes a callback function
    and returns a subroutine that calls it

=cut


sub handle_response{
    my $self = shift;
    my %params = @_;

    my $cb = $params{'cb'};
    return if !defined($cb);
    
    return sub {
	my $results = shift;
	&$cb($results);
    }
}

=head2 stop

Sends a shutdown signal on MPLS.FWDCTL.event.stop. Child processes
should listen for this signal and cleanly exit when received.

=cut

sub stop {
    my $self = shift;

    $self->{'logger'}->info("Sending MPLS.Discovery.stop to listeners");
    $self->{'rmq_client'}->{'topic'} = "MPLS.Discovery.Switch";
    $self->{'rmq_client'}->stop();
}    

1;
