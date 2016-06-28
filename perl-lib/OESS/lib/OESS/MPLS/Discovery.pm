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
use Socket;
use GRNOC::RabbitMQ::Client;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::WebService::Regex;
use OESS::Database;

use OESS::MPLS::Discovery::Interface;
use OESS::MPLS::Discovery::LSP;
use OESS::MPLS::Discovery::ISIS;

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
    #$self->{'isis'} = $self->_init_isis();
    #die if (!defined($self->{'isis'}));

    #create the client for talking to our Discovery switch objects!
    $self->{'rmq_client'} = GRNOC::RabbitMQ::Client->new( host => $self->{'db'}->{'rabbitMQ'}->{'host'},
							  port => $self->{'db'}->{'rabbitMQ'}->{'port'},
							  user => $self->{'db'}->{'rabbitMQ'}->{'user'},
							  pass => $self->{'db'}->{'rabbitMQ'}->{'pass'},
							  exchange => 'OESS',
							  topic => 'MPLS.Discovery');
    
    die if(!defined($self->{'rmq_client'}));

    #setup the timers
    $self->{'int_timer'} = AnyEvent->timer( after => 10, interval => 60, cb => sub { $self->int_handler(); });
    $self->{'lsp_timer'} = AnyEvent->timer( after => 10, interval => 60, cb => sub { $self->lsp_handler(); });
#    $self->{'isis_timer'} = AnyEvent->timer( after => 10, interval => 60, cb => sub { $self->isis_handler(); } );

    #our dispatcher for receiving events (only new_switch right now)    
    my $dispatcher = GRNOC::RabbitMQ::Dispatcher->new( host => $self->{'db'}->{'rabbitMQ'}->{'host'},
						       port => $self->{'db'}->{'rabbitMQ'}->{'port'},
						       user => $self->{'db'}->{'rabbitMQ'}->{'user'},
						       pass => $self->{'db'}->{'rabbitMQ'}->{'pass'},
						       exchange => 'OESS',
						       queue => 'MPLS-Discovery',
						       topic => "MPLS.Discovery.RPC");

    $self->register_rpc_methods( $dispatcher );
    $self->{'dispatcher'} = $dispatcher;

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

    my $node_id = $p_ref->{'node_id'}{'value'};

    #sherpa will you make my babies!
    $self->make_baby($node_id);
    $self->{'logger'}->debug("Baby was created!");
    sleep(5);
    $self->int_handler();
    $self->lsp_handler();
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
    $args{'topic'} = "MPLS.Discovery.Switch.";
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

#handlers for our timers
sub int_handler{
    my $self = shift;
    
    foreach my $node (@{$self->{'db'}->get_current_nodes(mpls => 1)}){
	$self->{'rmq_client'}->{'topic'} = "MPLS.Discovery.Switch." . $node->{'mgmt_addr'};
	$self->{'rmq_client'}->get_interfaces( async => 1,
					       async_callback => $self->handle_response( cb => sub { my $res = shift;
												     my $status = $self->{'interface'}->process_results( node => $node->{'name'}, interfaces => $res->{'results'});
											 }));
    }
}

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
												       warn "Still have pending\n";
												       $no_pending = 0;
												   }
											       }

											       if($no_pending){
												   my $status = $self->{'lsp'}->process_results( lsp => \%nodes);
											       }
										   })
					 
            );
    }
}

sub isis_handler{
    my $self = shift;


    my %nodes;
    foreach my $node (@{$self->{'db'}->get_current_nodes(mpls => 1)}){
	$nodes{$node->{'name'}} = {'pending' => 1};
        $self->{'rmq_client'}->{'topic'} = "MPLS.Discovery.Switch." . $node->{'mgmt_addr'};
        $self->{'rmq_client'}->get_isis_adjacencies( async => 1,
                                        async_callback => $self->handle_response( cb => sub { my $res = shift;
											      $nodes{$node->{'name'}} = $res;
											      $nodes{$node->{'name'}}->{'pending'} = 0;
											      my $no_pending = 1;
											      foreach my $node (keys %nodes){
												  if($nodes{$node}->{'pending'} == 1){
												      $no_pending = 0;
												  }
											      }
											      
											      if($no_pending){
												  my $status = $self->{'isis'}->process_results( node => $node, lsp => $res);
											      }
                                                                                  })
					
            );
    }
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
    

1;
