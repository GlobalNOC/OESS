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
use OESS::RabbitMQ::Topic qw(discovery_switch_topic_for_node);
use GRNOC::WebService::Client;
use GRNOC::WebService::Regex;
use OESS::Database;
use OESS::DB;
use JSON::XS;

use OESS::Config;
use OESS::MPLS::Discovery::Interface;
use OESS::MPLS::Discovery::LSP;
use OESS::MPLS::Discovery::ISIS;
use OESS::MPLS::Discovery::Paths;

use Time::HiRes qw( gettimeofday tv_interval);

use Log::Log4perl;

use AnyEvent;

use constant MPLS_TABLE => 'mpls.0';
use constant VPLS_TABLE => 'bgp.l2vpn.0';
use constant MAX_TSDS_MESSAGES => 30;
use constant TSDS_RIB_TYPE => 'rib_table';
use constant TSDS_PEER_TYPE => 'bgp_peer';
use constant VRF_STATS_INTERVAL => 60;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

=head2 new

instantiates a new OESS::MPLS::Discovery object, which intern creates
new instantiations of

    OESS::MPLS::Discovery::Interface
    OESS::MPLS::Discovery::LSP
    OESS::MPLS::Discovery::ISIS

this then schedules timed events to handle our data requests and
processing from the other modules.  This module also will handle new
device additions and initial device population

=cut
sub new {
    my $class = shift;
    my $args = {
        config     => '/etc/oess/database.xml',
        config_obj => undef,
        logger     => Log::Log4perl->get_logger('OESS.MPLS.Discovery'),
        test       => 0,
        @_
    };
    my $self = bless $args, $class;

    if (!defined $self->{config_obj}) {
        $self->{config_obj} = new OESS::Config(config_filename => $self->{config});
    }

    $self->{'db'} = new OESS::Database(config_obj => $self->{config_obj});
    $self->{'db2'} = new OESS::DB(config_obj => $self->{config_obj});
    die if (!defined $self->{'db'});
    die if (!defined $self->{'db2'});

    $self->{'interface'} = OESS::MPLS::Discovery::Interface->new(
        db => $self->{'db2'}
    );
    die "Unable to create Interface processor\n" if !defined $self->{'interface'}; 

    $self->{'isis'} = OESS::MPLS::Discovery::ISIS->new(db => $self->{'db'});
    die "Unable to create ISIS Processor\n" if !defined $self->{'isis'};

    $self->{'path'} = OESS::MPLS::Discovery::Paths->new(
        db => $self->{'db'},
        config_obj => $self->{config_obj}
    );
    die "Unable to create Path Processor\n" if !defined $self->{'path'};

    $self->{'tsds_svc'} = GRNOC::WebService::Client->new(
        url    => $self->{config_obj}->tsds_url . "/push.cgi",
        uid    => $self->{config_obj}->tsds_user,
        passwd => $self->{config_obj}->tsds_pass,
        realm  => $self->{config_obj}->tsds_realm,
        usePost => 1,
        debug   => 1
    );

    # Create the client for talking to our Discovery switch objects!
    $self->{'rmq_client'} = OESS::RabbitMQ::Client->new(
        config => $self->{'config_filename'},
        timeout => 120,
        topic => 'MPLS.Discovery'
    );
    die if (!defined $self->{'rmq_client'});

    # Create a child process for each switch
    $self->{'children'}  = {};
    $self->{'ipv4_intf'} = {};

    # If creating this object for testing skip creation of child
    # processes and child pollers.
    if ($self->{'test'}) {
        return $self;
    }

    $self->{'device_timer'} = AnyEvent->timer( after => 10, interval => 60, cb => sub { $self->device_handler(); });
    $self->{'int_timer'} = AnyEvent->timer( after => 60, interval => 120, cb => sub { $self->int_handler(); });
    $self->{'isis_timer'} = AnyEvent->timer( after => 80, interval => 120, cb => sub { $self->isis_handler(); });
    $self->{'vrf_stats_time'} = AnyEvent->timer( after => 20, interval => VRF_STATS_INTERVAL, cb => sub { $self->vrf_stats_handler(); });

    # Only lookup LSPs and Paths when network type is vpn-mpls.
    if ($self->{config_obj}->network_type eq 'vpn-mpls' || $self->{config_obj}->network_type eq 'nso+vpn-mpls') {
        $self->{'path_timer'} = AnyEvent->timer( after => 40, interval => 300, cb => sub { $self->path_handler(); });
    }

    # Dispatcher for receiving events (eg. A new switch was created).
    $self->{'dispatcher'} = OESS::RabbitMQ::Dispatcher->new(
        config_obj => $self->{config_obj},
        queue      => 'MPLS-Discovery',
        topic      => 'MPLS.Discovery.RPC'
    );
    $self->register_rpc_methods($self->{'dispatcher'});

    # When this process receives sigterm send an event to notify all
    # children to exit cleanly.
    $SIG{TERM} = sub {
        $self->stop();
    };

    my $nodes = $self->{'db'}->get_current_nodes(type => 'mpls');
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
    $self->{'logger'}->error("Inside is online discover");
    $method = GRNOC::RabbitMQ::Method->new( name  => "is_online",
                                            async => 1,
                           callback => sub { my $method = shift;
                                             $method->{'success_callback'}({successful => 1 }); },
                           description => "Checks if this service is onine and able to send repsonses back to monitoring");
    $d->register_method($method);
}

=head2 new_switch

this is called when a new switch is added to the network... the job of
this module is to add the device and its interfaces (and links) to the
OESS database for future provisioning use

=cut
sub new_switch{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    my $state_ref = shift;

    my $success = $m_ref->{'success_callback'};
    my $error   = $m_ref->{'error_callback'};

    my $node_id = $p_ref->{'node_id'}{'value'};

    # Respond to request immediately. It's Discovery's responsibility to create
    # any helper processes.
    &$success({status => FWDCTL_SUCCESS});

    #sherpa will you make my babies!
    $self->make_baby($node_id);
    $self->{'logger'}->debug("Baby was created!");
    sleep(5);
    $self->int_handler();

    return 1;
}


=head2 make_baby

make baby is a throw back to sherpa...  have to give Ed the credit for
most awesome function name ever

really this creates a switch object that can handle our RabbitMQ
requests and returns results from the device

=cut
sub make_baby{
    my $self = shift;
    my $id = shift;

    $self->{'logger'}->debug("Before the fork");
    if (defined $self->{'children'}->{$id}) {
        return 1;
    }

    my $node = $self->{'db'}->get_node_by_id(node_id => $id);

    my %args;
    $args{'id'} = $id;
    $args{'share_file'} = '/var/run/oess/mpls_share.'. $id;
    $args{'rabbitMQ_host'} = $self->{'db'}->{'rabbitMQ'}->{'host'};
    $args{'rabbitMQ_port'} = $self->{'db'}->{'rabbitMQ'}->{'port'};
    $args{'rabbitMQ_user'} = $self->{'db'}->{'rabbitMQ'}->{'user'};
    $args{'rabbitMQ_pass'} = $self->{'db'}->{'rabbitMQ'}->{'pass'};
    $args{'rabbitMQ_vhost'} = $self->{'db'}->{'rabbitMQ'}->{'vhost'};
    $args{'vendor'} = $node->{'vendor'};
    $args{'model'} = $node->{'model'};
    $args{'sw_version'} = $node->{'sw_version'};
    $args{'mgmt_addr'} = $node->{'mgmt_addr'};
    $args{'tcp_port'} = $node->{'tcp_port'};
    $args{'name'} = $node->{'name'};
    $args{'use_cache'} = 0;
    $args{'topic'} = "MPLS.Discovery.Switch";
    $args{'type'} = 'discovery';
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
    $args{"node"} = {"vendor" => $args{"vendor"}, "model" => $args{"model"}, "sw_version" => $args{"sw_version"}, "name" => $args{"name"}, "mgmt_addr" => $args{"mgmt_addr"}, "tcp_port" => $args{"tcp_port"}};			  
    $switch = OESS::MPLS::Switch->new( %args );
}')->fork->send_arg( %args )->run("run");

    $self->{'children'}->{$id} = {};
    $self->{'children'}->{$id}->{'rpc'} = 1;
}

=head2 int_handler

=cut
sub int_handler{
    my $self = shift;

    foreach my $node (@{$self->{'db'}->get_current_nodes(type => 'mpls')}) {

    $self->{logger}->info("Calling get_interfaces on $node->{name} $node->{mgmt_addr}.");
	$self->{'rmq_client'}->{'topic'} = discovery_switch_topic_for_node(mgmt_addr => $node->{'mgmt_addr'}, tcp_port => $node->{'tcp_port'});

	my $start = [gettimeofday];
	$self->{'rmq_client'}->get_interfaces(
            async_callback => $self->handle_response(
                cb => sub {
                    my $res = shift;
                    $self->{'logger'}->info("Called get_interfaces on $node->{name} $node->{mgmt_addr}. Response recieved in " . tv_interval($start,[gettimeofday]) . "s.");

                    foreach my $int (@{$res->{'results'}}) {
                        foreach my $addr (@{$int->{'addresses'}}) {
                            $self->{'ipv4_intf'}->{$addr} = $int->{'name'};
                        }
                    }

                    $self->{'db'}->update_node_operational_state(node_id => $node->{'node_id'}, state => 'up', protocol => 'mpls');
                    my $status = $self->{'interface'}->process_results( node => $node->{'name'}, interfaces => $res->{'results'});
                })
        );
    }
}

=head2 path_handler

=cut
sub path_handler {
    my $self = shift;

    if ($self->{config_obj}->oess_netconf_overlay ne 'vpn-mpls') {
        # Only lookup Paths when network type is set to vpn-mpls.
        return 1;
    }

    my $nodes = $self->{'db'}->get_current_nodes(type => 'mpls');
    if (!defined $nodes) {
        $self->{'logger'}->error("path_handler: Could not get current nodes.");
        return 0;
    }

    # Map from circuit ID to the list of LSPs associated with the circuit
    my %circuit_lsps;
    # Map from LSP name to the list of links currently used by the LSP
    # (or rather, for each link, it has the IP address of an endpoint)
    my %lsp_paths;

    my $cv = AnyEvent->condvar;
    $cv->begin(sub {
                   #now that we have all of the circuit LSPs and all of the LSP paths
                   #turn this into updates to the OESS DB!
                   $self->{'path'}->process_results(
                       circuit_lsps => \%circuit_lsps,
                       lsp_paths    => \%lsp_paths
                   );
               });

    # For each node, get the list of LSPs, and the associated circuits and paths
    foreach my $node (@{$nodes}) {
        $self->{'rmq_client'}->{'topic'} = discovery_switch_topic_for_node(mgmt_addr => $node->{'mgmt_addr'}, tcp_port => $node->{'tcp_port'});

        foreach my $table (MPLS_TABLE, VPLS_TABLE) {
            $cv->begin();
            $self->{'rmq_client'}->get_routed_lsps(
                table          => $table,
                async_callback => sub {
                    my $res = shift;
                    if(!defined($res->{'error'})){
                        foreach my $ckt (keys %{$res->{'results'}}){
                            $circuit_lsps{$ckt} = [] if !defined($circuit_lsps{$ckt});
                            push @{$circuit_lsps{$ckt}}, @{$res->{'results'}->{$ckt}};
                        }
                    }

                    $cv->end;
                });
        }

        $cv->begin();
        $self->{'rmq_client'}->get_lsp_paths(
            async_callback => sub {
                my $res = shift;
                if(!defined($res->{'error'})){
                    return if(!defined($res->{'results'}));
		    my %paths = %{$res->{'results'}};
                    foreach my $lsp (keys %paths){
                        $lsp_paths{$lsp} = [] if !defined($lsp_paths{$lsp});
                        push @{$lsp_paths{$lsp}}, @{$paths{$lsp}};
                    }
                }

                $cv->end;
            });
    }

    $cv->end;
}

=head2 isis_handler

=cut
sub isis_handler{
    my $self = shift;

    my %nodes;
    foreach my $node (@{$self->{'db'}->get_current_nodes(type => 'mpls')}) {
	$nodes{$node->{'short_name'}} = {'pending' => 1};
        $self->{'rmq_client'}->{'topic'} = discovery_switch_topic_for_node(mgmt_addr => $node->{'mgmt_addr'}, tcp_port => $node->{'tcp_port'});
        my $start = [gettimeofday];
        $self->{'rmq_client'}->get_isis_adjacencies( async_callback => $self->handle_response( cb => sub { my $res = shift;
													   $self->{'logger'}->debug("Total Time for get_isis_adjacencies " . $node->{'mgmt_addr'} . " call: " . tv_interval($start,[gettimeofday]));
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
sub device_handler {
    my $self =shift;

    foreach my $node (@{$self->{'db'}->get_current_nodes(type => 'mpls')}) {

        $self->{logger}->info("Calling get_system_info on $node->{name} $node->{mgmt_addr}.");
        $self->{'rmq_client'}->{'topic'} = discovery_switch_topic_for_node(mgmt_addr => $node->{'mgmt_addr'}, tcp_port => $node->{'tcp_port'});

        my $start = [gettimeofday];
        $self->{'rmq_client'}->get_system_info(async_callback => sub {
            my $response = shift;

            $self->{'logger'}->info("Called get_system_info on $node->{name} $node->{mgmt_addr}. Response recieved in " . tv_interval($start, [gettimeofday]) . "s.");
            if (defined $response->{'error'}) {
                $self->{'logger'}->error("Error from get_system_info on $node->{name} $node->{mgmt_addr}: $response->{error}");
                return;
            }

            $self->handle_system_info(node => $node->{'node_id'}, info => $response->{'results'});
        });
    }
}

=head2 vrf_stats_handler

=cut
sub vrf_stats_handler{
    my $self = shift;

    foreach my $node (@{$self->{'db'}->get_current_nodes(type => 'mpls')}) {
        $self->{'rmq_client'}->{'topic'} = discovery_switch_topic_for_node(mgmt_addr => $node->{'mgmt_addr'}, tcp_port => $node->{'tcp_port'});
	my $start = [gettimeofday];
	$self->{'rmq_client'}->get_vrf_stats( async_callback => $self->handle_response( cb => sub {
	    my $res = shift;
	    if(defined($res->{'error'})){
		my $addr = $node->{'mgmt_addr'};
		my $err = $res->{'error'};
		$self->{'logger'}->error("Error calling get_vrf_stats on $addr: $err");
		return;
	    }
	    $self->{'logger'}->debug("Total Time for get_vrf_stats " . $node->{'mgmt_addr'} . " call: " . tv_interval($start,[gettimeofday]));
	    $self->handle_vrf_stats(node => $node, stats => $res->{'results'});
        }));
    }
}

=head2 handle_vrf_stats

=cut
sub handle_vrf_stats{
    my $self = shift;
    my %params = @_;
    
    my $node = $params{'node'};
    my $stats = $params{'stats'};

    my $rib_stats = $stats->{'rib_stats'};
    my $peer_stats = $stats->{'peer_stats'};

    my $time = time();
    my $tsds_val = ();
    $self->{'logger'}->debug("Handling RIB stats: " . Dumper($rib_stats));
    return if(!defined($rib_stats));
    while (scalar(@$rib_stats) > 0){
        my $rib = shift @$rib_stats;
        my $meta = { routing_table => $rib->{'vrf'},
                     node => $node->{'name'}};

        delete $rib->{'vrf'};

        push(@$tsds_val, { type => TSDS_RIB_TYPE,
                           time => $time,
                           interval => VRF_STATS_INTERVAL,
                           values => $rib,
                           meta => $meta});

        if (scalar(@$tsds_val) >= MAX_TSDS_MESSAGES || scalar(@$rib_stats) == 0) {
            eval {
                my $tsds_res = $self->{'tsds_svc'}->add_data(data => encode_json($tsds_val));
                if (!defined $tsds_res) {
                    die $self->{'tsds_svc'}->get_error;
                }
                if (defined $tsds_res->{'error'}) {
                    die $tsds_res->{'error_text'};
                }
            };
            if ($@) {
                $self->{'logger'}->error("Error submitting results to TSDS: $@");
            }
            $tsds_val = ();
        }
    }

    $self->{'logger'}->debug("Handling Peer stats: " . Dumper($peer_stats));

    $self->{'db'}->_start_transaction();

    while (scalar(@$peer_stats) > 0){
        my $peer = shift @$peer_stats;
        my $meta = { peer_address => $peer->{'address'},
                     vrf => $peer->{'vrf'},
                     as => $peer->{'as'},
                     node => $node->{'name'}};

        my $prev =  $self->{'previous_peer'}->{$node->{'name'}}->{$peer->{'vrf'}}->{$peer->{'address'}};
        if(!defined($prev)){
            warn "No previous peer defined: " . Dumper($meta);
            $self->{'previous_peer'}->{$node->{'name'}}->{$peer->{'vrf'}}->{$peer->{'address'}} = $peer;
            next;
        }

        my $vals;
        
        $vals->{'output_messages'} = ($peer->{'output_messages'} - $prev->{'output_messages'}) / VRF_STATS_INTERVAL;
        $vals->{'input_messages'} = ($peer->{'input_messages'} - $prev->{'input_messages'}) / VRF_STATS_INTERVAL;
        $vals->{'route_queue_count'} = $peer->{'route_queue_count'};
        
        if($peer->{'state'} ne 'Established'){
            $vals->{'state'} = 0;
        }else{
            $vals->{'state'} = 1;
        }

        my $vrf = $peer->{'vrf'};
        my $vrf_id;
        if($vrf =~ /OESS-L3VPN/){
            $vrf =~ /OESS-L3VPN-(\d+)/;
            $vrf_id = $1;
        }

        warn "Processing VRF: " . $vrf . "\n";
        warn "VRF ID: " . $vrf_id . "\n";

        if(defined($vrf_id)){
            warn "Updating VRF EP Peer " . $peer->{'address'} . " with status: " . $vals->{'state'} . " in VRF: " . $vrf_id . "\n";
            my $res = $self->{'db'}->_execute_query("update vrf_ep_peer set operational_state = ? where peer_ip like ? and vrf_ep_id in (select vrf_ep_id from vrf_ep where vrf_id = ?)",[$vals->{'state'},$peer->{'address'} . "/%",$vrf_id]);
            warn Dumper($res);
        }

        $vals->{'flap_count'} = $peer->{'flap_count'};

        push(@$tsds_val, { type => TSDS_PEER_TYPE,
                           time => $time,
                           interval => VRF_STATS_INTERVAL,
                           values => $vals,
                           meta => $meta});

        if (scalar(@$tsds_val) >= MAX_TSDS_MESSAGES || scalar(@$peer_stats) == 0) {
            eval {
                my $tsds_res = $self->{'tsds_svc'}->add_data(data => encode_json($tsds_val));
                if (!defined $tsds_res) {
                    die $self->{'tsds_svc'}->get_error;
                }
                if (defined $tsds_res->{'error'}) {
                    die $tsds_res->{'error_text'};
                }
            };
            if ($@) {
                $self->{'logger'}->error("Error submitting results to TSDS: $@");
            }
            $tsds_val = ();
        }
    }
    $self->{'db'}->_commit();
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
    my $adjs = shift;

    my %node_info;

    my $nodes = $self->{'db'}->get_current_nodes(type => 'mpls');
    my $intfs = $self->{'ipv4_intf'};

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

    $self->{'logger'}->debug("Adjacencies: " . Dumper($adjs));
    $self->{'logger'}->debug("IPAddr map: " . Dumper($intfs));

    $self->{'db'}->_start_transaction();

    foreach my $node_a (keys %{$adjs}) {
        foreach my $intf_a (keys %{$adjs->{$node_a}}) {
            my $adj_a = $adjs->{$node_a}->{$intf_a};

            my $node_z = $adj_a->{'remote_node'};
            my $intf_z = $intfs->{$adj_a->{'remote_ip'}};

            if (!defined $adjs->{$node_z}) {
                $self->{logger}->warn("Couldn't find $node_z in adjacencies hash. A device's short name may be incorrectly set or may not be connected to OESS.");
                next;
            }

            my $adj_z = $adjs->{$node_z}->{$intf_z};

            if (!defined $adj_a || !defined $adj_z) {
                $self->{'logger'}->warn("Link Instantiation: Couldn't find remote adjacency for $node_a $intf_a");
                next;
            }

            my $a_int = $self->{'db'}->get_interface_id_by_names(node => $node_info{$node_a}->{'name'}, interface => $intf_a);
            my $z_int = $self->{'db'}->get_interface_id_by_names(node => $node_info{$node_z}->{'name'}, interface => $intf_z);
            if (!defined($a_int) || !defined($z_int)) {
                $self->{'logger'}->warn("Link Instantiation: Couldn't find interface_ids.");
                next;
            }

	    my ($link_db_id, $link_db_state) = $self->get_active_link_id_by_connectors(interface_a_id => $a_int, interface_z_id => $z_int);
            if ($link_db_id) {
                next;
            }

            my $links_a = $self->{'db'}->get_link_by_interface_id(interface_id => $a_int, show_decom => 0);
            my $links_z = $self->{'db'}->get_link_by_interface_id(interface_id => $z_int, show_decom => 0);

            my $a_node = $self->{'db'}->get_node_by_id(node_id => $node_info{$node_a}->{'node_id'});
            my $z_node = $self->{'db'}->get_node_by_id(node_id => $node_info{$node_z}->{'node_id'});

            my $a_links;
            my $z_links;

            # lets first remove any circuits not going to the node we want on these interfaces
            foreach my $link (@$links_a){
                my $other_int = $self->{'db'}->get_interface(interface_id => $link->{'interface_a_id'});
                if ($other_int->{'interface_id'} == $a_int) {
                    $other_int = $self->{'db'}->get_interface(interface_id => $link->{'interface_z_id'});
                }

                my $other_node = $self->{'db'}->get_node_by_id(node_id => $other_int->{'node_id'});
                if ($other_node->{'node_id'} == $z_node->{'node_id'}) {
                    push(@$a_links, $link);
                }
            }

            foreach my $link (@$links_z){
                my $other_int = $self->{'db'}->get_interface(interface_id => $link->{'interface_a_id'});
                if ($other_int->{'interface_id'} == $z_int) {
                    $other_int = $self->{'db'}->get_interface(interface_id => $link->{'interface_z_id'});
                }
                my $other_node = $self->{'db'}->get_node_by_id(node_id => $other_int->{'node_id'});
                if ($other_node->{'node_id'} == $a_node->{'node_id'}) {
                    push(@$z_links, $link);
                }
            }

            # we pretty much have 4 cases... there are 2 or more links going from a to z
            # there is 1 link going from a to z (this is enumerated as 2 elsifs one for each side)
            # there is no link going from a to z
            if (defined $a_links->[0] && defined $z_links->[0]) {
                #ok this is the more complex one to worry about
                #pick one and move it, we will have to move another one later
                my $link = $a_links->[0];
                my $old_z = $link->{'interface_a_id'};
                if ($old_z == $a_int) {
                    $old_z = $link->{'interface_z_id'};
                }

                my $old_z_interface = $self->{'db'}->get_interface(interface_id => $old_z);
                $self->{db}->update_interface_role(
                    interface_id =>  $old_z_interface->{interface_id},
                    role         =>  'unknown'
                );
                $self->{db}->update_interface_role(
                    interface_id =>  $z_int,
                    role         =>  'trunk'
                );

                $self->{'db'}->decom_link_instantiation(link_id => $link->{'link_id'});
                $self->{'db'}->create_link_instantiation(
                    link_id => $link->{'link_id'},
                    interface_a_id => $a_int,
                    interface_z_id => $z_int,
                    state => $link->{'state'},
                    mpls => 1,
                    ip_a => $adj_z->{'remote_ip'},
                    ip_z => $adj_a->{'remote_ip'}
                );
            } elsif (defined $a_links->[0]) {
                $self->{'logger'}->info("Link updated on the Z Side");

                #easy case update link_a so that it is now on the new interfaces
                my $link = $a_links->[0];
                my $old_z = $link->{'interface_a_id'};
                if ($old_z == $a_int) {
                    $old_z = $link->{'interface_z_id'};
                }

                my $old_z_interface = $self->{'db'}->get_interface(interface_id => $old_z);
                $self->{db}->update_interface_role(
                    interface_id =>  $old_z_interface->{interface_id},
                    role         =>  'unknown'
                );
                $self->{db}->update_interface_role(
                    interface_id =>  $z_int,
                    role         =>  'trunk'
                );

                #if its in the links_a that means the z end changed...
                $self->{'db'}->decom_link_instantiation(link_id => $link->{'link_id'});
                $self->{'db'}->create_link_instantiation(
                    link_id => $link->{'link_id'},
                    interface_a_id => $a_int,
                    interface_z_id => $z_int,
                    state => $link->{'state'},
                    mpls => 1,
                    ip_a => $adj_z->{'remote_ip'},
                    ip_z => $adj_a->{'remote_ip'}
                );
            } elsif (defined $z_links->[0]) {
                $self->{'logger'}->info("Link updated on the A Side");

                #easy case update link_a so that it is now on the new interfaces
                my $link = $z_links->[0];
                my $old_a = $link->{'interface_a_id'};
                if ($old_a == $z_int) {
                    $old_a = $link->{'interface_z_id'};
                }

                my $old_a_interface= $self->{'db'}->get_interface(interface_id => $old_a);
                $self->{db}->update_interface_role(
                    interface_id =>  $old_a_interface->{interface_id},
                    role         =>  'unknown'
                );
                $self->{db}->update_interface_role(
                    interface_id =>  $a_int,
                    role         =>  'trunk'
                );

                $self->{'db'}->decom_link_instantiation(link_id => $link->{'link_id'});
                $self->{'db'}->create_link_instantiation(
                    link_id => $link->{'link_id'},
                    interface_a_id => $a_int,
                    interface_z_id => $z_int,
                    state => $link->{'state'},
                    mpls => 1,
                    ip_a => $adj_z->{'remote_ip'},
                    ip_z => $adj_a->{'remote_ip'}
                );
            } else {
                my $link_name = $node_a . "-" . $intf_a . "--" . $node_z . "-" . $intf_z;
                my $link = $self->{'db'}->get_link_by_name(name => $link_name);
                my $link_id;

                if (!defined $link) {
                    $link_id = $self->{'db'}->add_link(name => $link_name);
                } else {
                    $link_id = $link->{'link_id'};
                }

                if (!defined $link_id) {
                    $self->{'db'}->_rollback();
                    return undef;
                }

                $self->{'db'}->create_link_instantiation(
                    link_id => $link_id,
                    state => 'available',
                    interface_a_id => $a_int,
                    interface_z_id => $z_int,
                    mpls => 1,
                    ip_a => $adj_z->{'remote_ip'},
                    ip_z => $adj_a->{'remote_ip'}
                );
            }
        }
    }

    $self->{'db'}->_commit();
    return 1;
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
    if(defined($link)){
        $link = @{$link}[0];
        print STDERR "Returning LinkID: " . $link->{'link_id'} . "\n";
        return ($link->{'link_id'}, $link->{'link_state'});
    }

    return undef;
}

=head2 handle_response

this returns a callback for when we get our sync data reply it looks
complicated but really it takes a callback function and returns a
subroutine that calls it

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
    $self->{'rmq_client'}->stop( no_reply => 1);

    $self->{'dispatcher'}->stop_consuming();
}    

1;
