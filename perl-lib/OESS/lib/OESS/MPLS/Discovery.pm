#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Discovery;

use GRNOC::RabbitMQ::Client;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Dispatcher;

use OESS::Database;

use OESS::MPLS::Discovery::Interface;
use OESS::MPLS::Discovery::LSP;
use OESS::MPLS::Discovery::IS-IS;

use Log::Log4perl;

use AnyEvent;

sub new{
    my $class = shift;
    my %args = (
        @_
        );

    my $self = \%args;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.Discovery');
    bless $self, $class;

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

    #setup the timers
    $self->{'int_timer'} = AnyEvent->timer( after => 10, interval => 60, cb => \&$self->int_handler);
    $self->{'lsp_timer'} = AnyEvent->timer( after => 10, interval => 60, cb => \&$self->lsp_handler);
    $self->{'isis_timer'} = AnyEvent->timer( after => 10, interval => 60, cb => \&$self->isis_handler);

    $self->{'rmq_client'} = GRNOC::RabbitMQ::Client->new( host => $self->{'db'}->{'rabbitMQ'}->{'host'},
							  port => $self->{'db'}->{'rabbitMQ'}->{'port'},
							  user => $self->{'db'}->{'rabbitMQ'}->{'user'},
							  pass => $self->{'db'}->{'rabbitMQ'}->{'pass'},
							  exchange => 'OESS',
							  queue => 'MPLS-Discovery',
							  topic => 'MPLS.Discovery');
        
    return $self;
}

#initialize our sub modules...
sub _init_interfaces{
    my $self = shift;
    
    my $ints = OESS::MPLS::Discovery::Interface->new( db => $self->{'db'},
						      lsp_processor => $self->lsp_handler );
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
												     my $status = $self->{'interface'}->process_result( node => $node, interfaces => $res);}
					       )
						    			 
	    );
    }
}

sub lsp_handler{
    my $self = shift;
    
    foreach my $node (@{$self->{'db'}->get_current_nodes(mpls => 1)}){
        $self->{'rmq_client'}->{'topic'} = "MPLS.Discovery.Switch." . $node->{'mgmt_addr'};
        $self->{'rmq_client'}->get_lsp( async => 1,
					async_callback => $self->handle_response( cb => sub { my $res = shift;
											      my $status = $self->{'lsp'}->process_result( node => $node, lsp => $res);
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
        $self->{'rmq_client'}->get_lsp( async => 1,
                                        async_callback => $self->handle_response( cb => sub { my $res = shift;
											      $nodes{$node->{'name'}} = $res;
											      my $no_pending = 1;
											      foreach my $node (keys %nodes){
												  if($node->{'pending'}){
												      $no_pending = 0;
												  }
											      }
											      
											      if($no_pending){
												  my $status = $self->{'isis'}->process_result( node => $node, lsp => $res);
											      }
                                                                                  })
					
            );
    }
}

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
