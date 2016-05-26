#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Discovery;

use AnyEvent::Fork;
use Socket;
use GRNOC::RabbitMQ::Client;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Dispatcher;

use OESS::Database;

use OESS::MPLS::Discovery::Interface;
use OESS::MPLS::Discovery::LSP;
use OESS::MPLS::Discovery::ISIS;

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

    $self->{'rmq_client'} = GRNOC::RabbitMQ::Client->new( host => $self->{'db'}->{'rabbitMQ'}->{'host'},
							  port => $self->{'db'}->{'rabbitMQ'}->{'port'},
							  user => $self->{'db'}->{'rabbitMQ'}->{'user'},
							  pass => $self->{'db'}->{'rabbitMQ'}->{'pass'},
							  exchange => 'OESS',
							  queue => 'MPLS-Discovery-Client',
							  topic => 'MPLS.Discovery');

    die if(!defined($self->{'rmq_client'}));
        
    #setup the timers
    $self->{'int_timer'} = AnyEvent->timer( after => 10, interval => 60, cb => sub { $self->int_handler() });
    $self->{'lsp_timer'} = AnyEvent->timer( after => 10, interval => 60, cb => sub { $self->lsp_handler() });
    $self->{'isis_timer'} = AnyEvent->timer( after => 10, interval => 60, cb => sub { $self->isis_handler()} );
    $self->{'repopulate_device'} = AnyEvent->timer( after => 10, interval => 60, cb => sub { $self->populate_devices() } );

    
    my $dispatcher = GRNOC::RabbitMQ::Dispatcher->new( host => $self->{'db'}->{'rabbitMQ'}->{'host'},
                                                              port => $self->{'db'}->{'rabbitMQ'}->{'port'},
                                                              user => $self->{'db'}->{'rabbitMQ'}->{'user'},
                                                              pass => $self->{'db'}->{'rabbitMQ'}->{'pass'},
                                                              exchange => 'OESS',
                                                              queue => 'MPLS-Discovery',
                                                              topic => "MPLS.Discovery.RPC");

    $self->register_rpc_methods( $dispatcher );
    $self->{'dispatcher'} = $dispatcher;

    my $nodes = $self->{'db'}->get_current_nodes( mpls => 1);
    foreach my $node (@$nodes) {
	$self->make_baby($node->{'node_id'});
    }

    return $self;
}

sub register_rpc_methods{
    my $self = shift;
    my $d = shift;
    my $method = GRNOC::RabbitMQ::Method->new( name => "new_switch",
					    callback => sub { $self->new_switch(@_) },
					    description => "adds a new switch to the DB and starts a child process to fetch its details");
    
    $method->add_input_parameter( name => "ip",
                                  description => "the ip address of the switch",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::IP_ADDRESS);

    $method->add_input_parameter( name => "username",
                                  description => "the ip address of the switch",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NAME_ID);

    $method->add_input_parameter( name => "password",
                                  description => "the ip address of the switch",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::TEXT);

    $method->add_input_parameter( name => "vendor",
                                  description => "the ip address of the switch",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NAME_ID);

    $method->add_input_parameter( name => "model",
                                  description => "the ip address of the switch",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NAME_ID);

    $method->add_input_parameter( name => "sw_version",
                                  description => "the ip address of the switch",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NAME_ID);
	
    $d->register_method($method);
}

sub new_switch{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    my $state_ref = shift;

    my $ip = $p_ref->{'ip'}{'value'};
    my $password = $p_ref->{'password'}{'value'};
    my $username = $p_ref->{'username'}{'value'};
    my $vendor = $p_ref->{'vendor'}{'value'};
    my $model = $p_ref->{'model'}{'value'};
    my $sw_rev = $p_ref->{'version'}{'value'};

    my $node = $self->{'db'}->get_node_by_ip( ip => $ip );
    if(defined($node)){
	if(!$node->{'mpls'}){
	    #TODO: update the node instantiation to allow for MPLS
	    
	}
	$self->{'logger'}->debug("This switch already exists!");
	$self->update_cache(-1);	
	#sherpa will you make my babies!
	$self->make_baby($node->{'node_id'});
	$self->{'logger'}->debug("Baby was created!");
        return;
    }

    #first we need to create the node entry in the db...
    #also set the node instantiation to available...
    my $node_name;
    # try to look up the name first to be all friendly like
    $node_name = gethostbyaddr($ip, AF_INET);

    # avoid any duplicate host names. The user can set this to whatever they want
    # later via the admin interface.
    my $i = 1;
    my $tmp = $node_name;
    while (my $result = $self->{'db'}->get_node_by_name(name => $tmp)){
        $tmp = $node_name . "-" . $i;
        $i++;
    }

    $node_name = $tmp;

    # default
    if (! $node_name){
        $node_name="unnamed-".$ip;
    }

    $self->{'db'}->_start_transaction();

    my $node_id = $self->{'db'}->add_node(name => $node_name, operational_state => 'up', network_id => 1);
    if(!defined($node_id)){
        $self->{'db'}->_rollback();
        return;
    }
    $self->{'db'}->create_node_instance(node_id => $node_id, mgmt_addr => $ip, admin_state => 'available', username => $username, password => $password, vendor => $vendor, model => $model, sw_version => $sw_rev, mpls => 1, openflow => 0);
    $self->{'db'}->_commit();

    $self->update_cache(-1);

    #sherpa will you make my babies!
    $self->make_baby($node_id);
    $self->{'logger'}->debug("Baby was created!");
}


=head2 make_baby
make baby is a throw back to sherpa...
have to give Ed the credit for most
awesome function name ever
=cut
sub make_baby{
    my $self = shift;
    my $id = shift;

    $self->{'logger'}->debug("Before the fork");

    my $node = $self->{'node_by_id'}->{$id};

    my %args;
    $args{'id'} = $id;
    $args{'share_file'} = $self->{'share_file'}. "." . $id;
    $args{'rabbitMQ_host'} = $self->{'db'}->{'rabbitMQ'}->{'host'};
    $args{'rabbitMQ_port'} = $self->{'db'}->{'rabbitMQ'}->{'port'};
    $args{'rabbitMQ_user'} = $self->{'db'}->{'rabbitMQ'}->{'user'};
    $args{'rabbitMQ_pass'} = $self->{'db'}->{'rabbitMQ'}->{'pass'};
    $args{'rabbitMQ_vhost'} = $self->{'db'}->{'rabbitMQ'}->{'vhost'};
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
    $switch = OESS::MPLS::Switch->new( %args );
    }')->fork->send_arg( %args )->run("run");

    $self->{'children'}->{$id}->{'rpc'} = 1;
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
#        $self->{'rmq_client'}->get_LSPs( async => 1,
#					 async_callback => $self->handle_response( cb => sub { my $res = shift;
#											       my $status = $self->{'lsp'}->process_result( node => $node, lsp => $res);
#										   })
#					
#            );
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

sub populate_devices{
    my $self = shift;

    foreach my $node (keys %{$self->{'node_by_id'}}){
        $self->{'fwdctl_events'}->{'topic'} = "MPLS.Discovery.Switch." . $self->{'node_by_id'}->{$node}->{'mgmt_addr'};
        $self->{'fwdctl_events'}->get_interfaces( async_callback => sub {
            my $res = shift;
            my $ints = $res->{'results'};
            $self->{'logger'}->debug("Populating interfaces!!!");
            $self->{'db'}->_start_transaction();
	    
            foreach my $int (@$ints){
                $self->{'logger'}->debug("INTERFACE: " . Data::Dumper::Dumper($int));
                my $int_id = $self->{'db'}->add_or_update_interface(node_id => $node, name => $int->{'name'}, description => $int->{'description'}, operational_state => $int->{'operational_state'}, port_num => $int->{'snmp_index'}, admin_state => $int->{'snmp_index'}, mpls => 1);
		
            }
            $self->{'db'}->_commit();
                                                  });
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
