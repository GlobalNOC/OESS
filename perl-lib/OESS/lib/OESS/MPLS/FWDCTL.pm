use strict;
use warnings;

###############################################################################
package OESS::MPLS::FWDCTL;

use Data::Dumper;
use Log::Log4perl;
use Socket;

use OESS::Config;
use OESS::Database;
use OESS::Topology;
use OESS::Circuit;
use OESS::L2Circuit;
use OESS::VRF;

#anyevent
use AnyEvent;
use AnyEvent::Fork;

use GRNOC::RabbitMQ::Client;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use OESS::RabbitMQ::Client;
use OESS::RabbitMQ::Dispatcher;

use OESS::DB;
use OESS::DB::Circuit;
use OESS::VRF;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;
use constant FWDCTL_BLOCKED     => 4;

use constant PENDING_DIFF_NONE  => 0;
use constant PENDING_DIFF       => 1;
use constant PENDING_DIFF_ERROR => 2;

#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;

#circuit statuses
use constant OESS_CIRCUIT_UP    => 1;
use constant OESS_CIRCUIT_DOWN  => 0;
use constant OESS_CIRCUIT_UNKNOWN => 2;

use constant TIMEOUT => 3600;

use JSON::XS;
use GRNOC::WebService::Regex;

=head2 new

create a new OESS Master process

  FWDCTL->new();

=cut

sub new {
    my $class = shift;
    my %params = @_;
    my $self = \%params;
    bless $self, $class;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.FWDCTL.MASTER');

    my $config_filename = (defined $self->{'config'}) ? $self->{'config'} : '/etc/oess/database.xml';
    $self->{'config'} = new OESS::Config(config_filename => $config_filename);

    $self->{'db'} = OESS::Database->new( config_file => $config_filename );
    $self->{'db2'} = OESS::DB->new();
    my $fwdctl_dispatcher = OESS::RabbitMQ::Dispatcher->new( queue => 'MPLS-FWDCTL',
                                                             topic => "MPLS.FWDCTL.RPC");

    $self->_register_rpc_methods( $fwdctl_dispatcher );

    $self->{'fwdctl_dispatcher'} = $fwdctl_dispatcher;


    $self->{'fwdctl_events'} = OESS::RabbitMQ::Client->new(
        timeout => 120,
        topic => 'MPLS.FWDCTL.event'
    );


    $self->{'logger'}->info("RabbitMQ ready to go!");

    # When this process receives sigterm send an event to notify all
    # children to exit cleanly.
    $SIG{TERM} = sub {
        $self->stop();
    };


    my $topo = OESS::Topology->new( db => $self->{'db'}, MPLS => 1 );
    if (! $topo) {
        $self->{'logger'}->fatal("Could not initialize topo library");
        exit(1);
    }
    
    $self->{'topo'} = $topo;
    
    $self->{'uuid'} = new Data::UUID;
    
    if(!defined($self->{'share_file'})){
        $self->{'share_file'} = '/var/run/oess/mpls_share';
    }
    
    $self->{'circuit'} = {};
    $self->{'node_rules'} = {};
    $self->{'link_status'} = {};
    $self->{'circuit_status'} = {};
    $self->{'node_info'} = {};
    $self->{'link_maintenance'} = {};
    $self->{'node_by_id'} = {};

    $self->update_cache(
        { success_callback => sub { }, error_callback => sub { } },
        { circuit_id => { value => -1 } }
    );

    #from TOPO startup
    my $nodes = $self->{'db'}->get_current_nodes(type => 'mpls');
    foreach my $node (@$nodes) {
	warn Dumper($node);
	$self->make_baby($node->{'node_id'});
    }

    
    $self->{'logger'}->error("MPLS Provisioner INIT COMPLETE");

    $self->{'events'} = {};
    
    return $self;
}

=head2 build_cache

builds the cache for it to work off of

=cut

sub build_cache{
    my %params = @_;
   
    my $db = $params{'db'};
    my $db2 = $params{'db2'};
    my $logger = $params{'logger'};

    die if(!defined($logger));

    #basic assertions
    $logger->error("DB was not defined") && $logger->logcluck() && exit 1 if !defined($db);
    $logger->error("DB Version does not match expected version") && $logger->logcluck() && exit 1 if !$db->compare_versions();


    $logger->debug("Fetching State from the DB");
    # my $circuits = $db->get_current_circuits( type => 'mpls');
    my $circuits = OESS::DB::Circuit::fetch_circuits(db => $db2, state => 'active');
    warn Dumper($circuits);

    #init our objects
    my %ckts;
    my %vrfs;
    my %circuit_status;
    my %link_status;
    my %node_info;
    foreach my $circuit (@$circuits) {
	$logger->error("Updating Cache for circuit: " . $circuit->{'circuit_id'});
        my $id = $circuit->{'circuit_id'};
        my $ckt = OESS::L2Circuit->new(
            db => $db2,
            circuit_id => $id
        );
        $ckts{ $ckt->circuit_id() } = $ckt;
        
        my $operational_state = $circuit->{'details'}->{'operational_state'};
        if ($operational_state eq 'up') {
            $circuit_status{$id} = OESS_CIRCUIT_UP;
        } elsif ($operational_state  eq 'down') {
            $circuit_status{$id} = OESS_CIRCUIT_DOWN;
        } else {
            $circuit_status{$id} = OESS_CIRCUIT_UNKNOWN;
        }
    }
        
    my $links = $db->get_current_links(type => 'mpls');
    foreach my $link (@$links) {
        if ($link->{'status'} eq 'up') {
            $link_status{$link->{'name'}} = OESS_LINK_UP;
        } elsif ($link->{'status'} eq 'down') {
            $link_status{$link->{'name'}} = OESS_LINK_DOWN;
        } else {
            $link_status{$link->{'name'}} = OESS_LINK_UNKNOWN;
        }
    }

    my $vrfs = OESS::DB::VRF::get_vrfs(db => $db2, state => 'active');

    foreach my $vrf (@$vrfs){
	$logger->error("Updating Cache for VRF: " . $vrf->{'vrf_id'});
	
	$vrf = OESS::VRF->new(db => $db2, vrf_id => $vrf->{'vrf_id'});

        if(!defined($vrf)){
            warn "Unable to process VRF: " . $vrf->{'vrf_id'} . "\n";
            $logger->error("Unable to process VRF: " . $vrf->{'vrf_id'});

            next;
        }

	$vrfs{ $vrf->vrf_id() } = $vrf;
    }
        
    my $nodes = $db->get_current_nodes(type => 'mpls');
    foreach my $node (@$nodes) {
        my $details = $db->get_node_by_id(node_id => $node->{'node_id'});
	next if(!$details->{'mpls'});
        $details->{'node_id'} = $details->{'node_id'};
	$details->{'id'} = $details->{'node_id'};
        $details->{'name'} = $details->{'name'};
	$details->{'ip'} = $details->{'ip'};
	$details->{'vendor'} = $details->{'vendor'};
	$details->{'model'} = $details->{'model'};
	$details->{'sw_version'} = $details->{'sw_version'};
        $details->{'pending_diff'} = $details->{'pending_diff'};;
	$node_info{$node->{'name'}} = $details;
    }

    return {ckts => \%ckts, circuit_status => \%circuit_status, link_status => \%link_status, node_info => \%node_info, vrfs => \%vrfs};
}

=head2 convert_graph_to_mpls

converts the graph object into next hop addresses for the MPLS path

=cut

sub convert_graph_to_mpls{
    my $self = shift;
    my $graph = shift;
    my $node_a = shift;
    my $node_z = shift;

    my @hops = $graph->SP_Dijkstra($node_a, $node_z);
	
    my @res;
    foreach my $link (@hops){
	push(@res, $self->{'node_info'}->{$link->{'node_z'}}->{'router_ip'});
    }

    return \@res;
}

sub _write_cache{
    my $self = shift;
    $self->{'logger'}->info("called _write_cache");

    my %switches;

    foreach my $vrf_id (keys (%{$self->{'vrfs'}})){
        $self->{'logger'}->debug("Writing VRF $vrf_id to cache.");
        my $vrf = $self->get_vrf_object($vrf_id);
        if (!defined $vrf) {
            $self->{'logger'}->error("VRF $vrf_id could't be loaded or written to cache.");
        }

        my $eps = $vrf->endpoints();

        my @ints;
        foreach my $ep (@$eps){
            my $int_obj = $ep->to_hash;

            if (defined $switches{$ep->node()}->{'vrfs'}{$vrf->vrf_id()}) {
                push(@{$switches{$ep->node()}->{'vrfs'}{$vrf->vrf_id()}{'interfaces'}}, $int_obj);
            } else {
                $switches{$ep->node()}->{'vrfs'}{$vrf->vrf_id()} = {
                    name => $vrf->name(),
                    vrf_id => $vrf->vrf_id(),
                    interfaces => [$int_obj],
                    prefix_limit => $vrf->prefix_limit(),
                    state => $vrf->state(),
                    local_asn => $vrf->local_asn(),
                };
            }
        }
    }

    foreach my $ckt_id (keys (%{$self->{'circuit'}})){
        my $found = 0;
        next if $self->{'circuit'}->{$ckt_id}->{'type'} ne 'mpls';

        $self->{'logger'}->debug("Writing Circuit $ckt_id to cache.");
        my $ckt = $self->get_ckt_object($ckt_id);
        if (!defined $ckt) {
            $self->{'logger'}->error("Circuit $ckt_id couldn't be loaded or written to cache.");
            next;
        }
        my $details = $ckt->to_hash();
        my $eps = $ckt->endpoints();

        my $ckt_type;
        if ($self->{'config'}->network_type eq 'evpn-vxlan') {
            $ckt_type = "EVPN";
        } else {
            $ckt_type = "L2VPN";

            my $primary_path = $ckt->path(type => 'primary');
            if (defined $primary_path && @{$primary_path->links} > 0) {
                $ckt_type = "L2CCC";
            }

            if(scalar(@$eps) > 2){
                $ckt_type = "L2VPLS";
            }
        }

        my $site_id = 0;
        foreach my $ep_a (@$eps){
            my @ints;
            push(@ints, $ep_a->to_hash);

            $site_id++;
            my $paths = [];
            my $touch = {};

            if(defined($switches{$ep_a->{'node'}}->{'ckts'}{$details->{'circuit_id'}})){
                next;
            }

            foreach my $ep_z (@$eps){

                # Ignore interations comparing the same endpoint.
                next if ($ep_a->{'node'} eq $ep_z->{'node'} && $ep_a->{'interface'} eq $ep_z->{'interface'} && $ep_a->{'tag'} eq $ep_z->{'tag'} && $ep_a->{'inner_tag'} eq $ep_z->{'inner_tag'});

                if ($ep_a->{'node'} eq $ep_z->{'node'}){
                    # We're comparing interfaces on the same node; There
                    # are no path calculations to be made.
                    #
                    # Because we are only creating a single circuit
                    # object per node, we should include any other
                    # interface we see on $ep_a->{'node'}.
                    push(@ints, $ep_z->to_hash);
                    next;
                }

                if (exists $touch->{$ep_z->{'node'}}) {
                    # A path from $ep_a to $ep_z has already been
                    # calculated; Skip path calculations.
                    #
                    # Because this endpoint is remote to $ep_a we do not
                    # add the interface to @ints.
                    next;
                }
                $touch->{$ep_z->{'node'}} = 1;


                my $primary = $ckt->get_path(path => 'primary');
                if (!defined $primary) {
                    push @$paths, {
                        name           => 'PRIMARY',
                        mpls_path_type => 'loose',
                        dest           => $self->{node_info}->{$ep_z->{node}}->{loopback_address},
                        dest_node      => $self->{node_info}->{$ep_z->{node}}->{node_id}
                    };
                } else {
                    my $loopback_a = $self->{node_info}->{$ep_a->{node}}->{loopback_address};
                    my $loopback_z = $self->{node_info}->{$ep_z->{node}}->{loopback_address};
                    push @$paths, {
                        name           => 'PRIMARY',
                        mpls_path_type => 'strict',
                        path           => $primary->hops($loopback_a, $loopback_z),
                        dest           => $self->{node_info}->{$ep_z->{node}}->{loopback_address},
                        dest_node      => $self->{node_info}->{$ep_z->{node}}->{node_id}
                    };

                    push @$paths, {
                        name           => 'TERTIARY',
                        dest           => $self->{node_info}->{$ep_z->{node}}->{loopback_address},
                        mpls_path_type => 'loose',
                        dest_node      => $self->{node_info}->{$ep_z->{node}}->{node_id}
                    };
                }

                # Because the path hops are specific to the direction
                # my $primary = $ckt->get_mpls_path_type( path => 'primary');

                # if(!defined($primary) || $primary eq 'none' || $primary eq 'loose'){
                #     #either we have a none or a loose type for mpls type... or its not defined... in any case... use a loose path
                #     push(@$paths,{ name => 'PRIMARY',  
                #                    mpls_path_type => 'loose',
                #                    dest => $self->{'node_info'}->{$ep_z->{'node'}}->{'loopback_address'},
                #                    dest_node => $self->{'node_info'}->{$ep_z->{'node'}}->{'node_id'}});
                # }else{
                #     #ok so they specified a strict path... get the LSPs
                #     push(@$paths,{ name => 'PRIMARY', mpls_path_type => 'strict',
                #                    path => $ckt->get_mpls_hops( path => 'primary',
                #                                                 start => $ep_a->{'node'},
                #                                                 end => $ep_z->{'node'}),
                #                    dest => $self->{'node_info'}->{$ep_z->{'node'}}->{'loopback_address'},
                #                    dest_node => $self->{'node_info'}->{$ep_z->{'node'}}->{'node_id'}
                #                });

                #     my $backup = $ckt->get_mpls_path_type( path => 'backup');

                #     if(!defined($backup) || $backup eq 'none' || $backup eq 'loose'){
                #         push(@$paths,{ name => 'SECONDARY', 
                #                        mpls_path_type => 'loose',
                #                        dest => $self->{'node_info'}->{$ep_z->{'node'}}->{'loopback_address'},
                #                        dest_node => $self->{'node_info'}->{$ep_z->{'node'}}->{'node_id'}});
                #     }else{
                #         push(@$paths,{ name => 'SECONDARY',
                #                        mpls_path_type => 'strict',
                #                        path => $ckt->get_mpls_hops( path => 'backup',
                #                                                     start => $ep_a->{'node'},
                #                                                     end => $ep_z->{'node'}),
                #                        dest => $self->{'node_info'}->{$ep_z->{'node'}}->{'loopback_address'},
                #                        dest_node => $self->{'node_info'}->{$ep_z->{'node'}}->{'node_id'}
                #                    });
                #         #our tertiary path...
                #         push(@$paths,{ name => 'TERTIARY',
                #                        dest => $self->{'node_info'}->{$ep_z->{'node'}}->{'loopback_address'},
                #                        mpls_path_type => 'loose',
                #                        dest_node => $self->{'node_info'}->{$ep_z->{'node'}}->{'node_id'}
                #                    });
                #     }
                # }	
            }

            $self->{'logger'}->debug("Adding Circuit: " . $ckt->name() . " to cache for node: " . $ep_a->{'node'});

            if(scalar(@$paths) == 0){
                # All observed endpoints are on the same node; Use VPLS.
                $ckt_type = "L2VPLS";
            }

            my $obj = { circuit_name => $ckt->name(),
                        interfaces => \@ints,
                        paths => $paths,
                        ckt_type => $ckt_type,
                        site_id => $site_id,
                        a_side => $ep_a->{'node_id'},
                        state  => $ckt->state()
                    };

            $switches{$ep_a->{'node'}}->{'ckts'}{$details->{'circuit_id'}} = $obj;
        }
    }

    foreach my $node (keys %{$self->{'node_info'}}){
	my $data;
	$data->{'nodes'} = $self->{'node_by_id'};
	$data->{'ckts'} = $switches{$node}->{'ckts'};
    $data->{'vrfs'} = $switches{$node}->{'vrfs'};
	$self->{'logger'}->info("writing shared file for node_id: " . $self->{'node_info'}->{$node}->{'id'});

	my $file = $self->{'share_file'} . "." . $self->{'node_info'}->{$node}->{'id'};
	open(my $fh, ">", $file) or $self->{'logger'}->error("Unable to open $file " . $!);
        print $fh encode_json($data);
        close($fh);
    }

}

sub _register_rpc_methods{
    my $self = shift;
    my $d = shift;

    my $method = GRNOC::RabbitMQ::Method->new( name => "addVlan",
                                               async => 1,
					       callback => sub { $self->addVlan(@_) },
					       description => "adds a VLAN to the network that exists in OESS DB");
    
    $method->add_input_parameter( name => "circuit_id",
				  description => "the circuit ID to add",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::INTEGER);
    
    $d->register_method($method);


    $method = GRNOC::RabbitMQ::Method->new( name => "addVrf",
                                            async => 1,
                                            callback => sub { $self->addVrf(@_) },
                                            description => "adds a VRF to the network that exists in OESS DB");
    
    $method->add_input_parameter( name => "vrf_id",
                                  description => "the vrf ID to add",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);

    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => "delVrf",
                                            async => 1,
                                            callback => sub { $self->delVrf(@_) },
                                            description => "remove a VRF to the network that exists in OESS DB");

    $method->add_input_parameter( name => "vrf_id",
                                  description => "the vrf ID to add",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);

    $d->register_method($method);
    
    $method = GRNOC::RabbitMQ::Method->new( name => "deleteVlan",
                                            async => 1,
					    callback => sub { $self->deleteVlan(@_) },
					    description => "deletes a VLAN to the network that exists in OESS DB");
    
    $method->add_input_parameter( name => "circuit_id",
                                  description => "the circuit ID to delete",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);
    
    $d->register_method($method);
    
    
    $method = GRNOC::RabbitMQ::Method->new( name => 'update_cache',
                                            async => 1,
					    callback => sub { $self->update_cache(@_) },
					    description => 'Updates the circuit cache');

    
    $method->add_input_parameter( name => "circuit_id",
                                  description => "the circuit ID to update",
                                  required => 0,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);

    $method->add_input_parameter( name => "node_id",
                                  description => "the node ID to update",
                                  required => 0,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);

    $method->add_input_parameter( name => "vrf_id",
                                  description => "the vrf ID to update",
                                  required => 0,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);

    $d->register_method($method);
    
    $method = GRNOC::RabbitMQ::Method->new( name => 'get_event_status',
					    callback => sub { $self->get_event_status(@_) },
					    description => "Returns the current status of the event");

    $method->add_input_parameter( name => "event_id",
                                  description => "the event id to fetch the current state of",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NAME_ID);

    $d->register_method($method);

    
    $method = GRNOC::RabbitMQ::Method->new( name => 'check_child_status',
					    callback => sub { $self->check_child_status(@_) },
					    description => "Returns an event id which will return the final status of all children");
    
    $d->register_method($method);
   
    $method = GRNOC::RabbitMQ::Method->new( name => 'echo',
                                            callback => sub { $self->echo(@_) },
                                            description => "Always returns 1" );
    $d->register_method($method);
    
    $method = GRNOC::RabbitMQ::Method->new( name => 'new_switch',
                                            async => 1,
                                            callback => sub { $self->new_switch(@_) },
                                            description => "adds a new switch by node_id" );
    
    $method->add_input_parameter( name => "node_id",
                                  description => "the node ID to be added",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);

    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => 'get_diff_text',
                                            async => 1,
                                            callback => sub { $self->get_diff_text(@_); },
                                            description => "Returns a human readable diff for node_id" );
    $method->add_input_parameter( name => "node_id",
                                  description => "The node ID to lookup",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);
    $d->register_method($method);

}

=head2 new_switch

handles the case of adding a new switch

=cut

sub new_switch{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    my $state_ref = shift;

    my $node_id = $p_ref->{'node_id'}{'value'};
    
    my $success = $m_ref->{'success_callback'};

    $self->make_baby($node_id);
    $self->{'logger'}->debug("Baby was created!");
    $self->update_cache(
        { success_callback => sub { }, error_callback => sub { } },
        { circuit_id => { value => -1 } }
    );

    &$success({status => FWDCTL_SUCCESS});
}

=head2 create_nodes

Checks $self->{'pending_nodes'} for any nodes that are pending creation.

=cut
sub create_nodes {

}

=head2 make_baby

make baby is a throw back to sherpa...
have to give Ed the credit for most 
awesome function name ever

=cut
sub make_baby {
    my $self = shift;
    my $id = shift;
    
    return 1 if(defined($self->{'children'}->{$id}->{'rpc'}) && $self->{'children'}->{$id}->{'rpc'} == 1);

    $self->{'logger'}->debug("Before the fork");
    
    my $node = $self->{'node_by_id'}->{$id};
    my %args;
    $args{'id'} = $id;
    $args{'config'} = $self->{'config'}->{'config_filename'};
    $args{'share_file'} = $self->{'share_file'}. "." . $id;
    $args{'rabbitMQ_host'} = $self->{'db'}->{'rabbitMQ'}->{'host'};
    $args{'rabbitMQ_port'} = $self->{'db'}->{'rabbitMQ'}->{'port'};
    $args{'rabbitMQ_user'} = $self->{'db'}->{'rabbitMQ'}->{'user'};
    $args{'rabbitMQ_pass'} = $self->{'db'}->{'rabbitMQ'}->{'pass'};
    $args{'rabbitMQ_vhost'} = $self->{'db'}->{'rabbitMQ'}->{'vhost'};
    $args{'topic'} = "MPLS.FWDCTL.Switch";
    my $proc = AnyEvent::Fork->new->require("Log::Log4perl", "OESS::MPLS::Switch")->eval('
use strict;
use warnings;

my $switch;
my $logger;

Log::Log4perl::init_and_watch("/etc/oess/logging.conf",10);
sub run{
    my $fh = shift;
    my %args = @_;

    $logger = Log::Log4perl->get_logger("OESS.MPLS.FWDCTL.MASTER");
    $logger->info("Creating child for id: " . $args{"id"});
    $logger->info($args{"config"});
    $switch = OESS::MPLS::Switch->new( %args );
}')->fork->send_arg( %args )->run("run");

    my $topic  = "MPLS.FWDCTL.Switch." . $self->{'node_by_id'}->{$id}->{'mgmt_addr'};

    $self->{'children'}->{$id}->{'rpc'} = 1;
    $self->{'children'}->{$id}->{'pending_diff'} = $node->{'pending_diff'};
    return 1;
}

=head2 update_cache

updates the cache for all of the children

=cut
sub update_cache {
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $success = $m_ref->{'success_callback'};
    my $error   = $m_ref->{'error_callback'};

    my $circuit_id = $p_ref->{'circuit_id'}{'value'};
    my $node_id =  $p_ref->{'node_id'}{'value'};
    my $vrf_id = $p_ref->{'vrf_id'}{'value'};

    if ((!defined($circuit_id) || $circuit_id == -1 ) && (!defined($vrf_id) || $vrf_id == -1)) {
        $self->{'logger'}->debug("Updating Cache for entire network.");

        my $res = build_cache(db => $self->{'db'}, logger => $self->{'logger'}, db2 => $self->{'db2'});
        $self->{'circuit'} = $res->{'ckts'};
        $self->{'vrfs'} = $res->{'vrfs'};
        $self->{'link_status'} = $res->{'link_status'};
        $self->{'circuit_status'} = $res->{'circuit_status'};
        $self->{'node_info'} = $res->{'node_info'};
        $self->{'logger'}->debug("Cache update complete");

        #want to reference by name and by id
        my %node_by_id;
        foreach my $node (keys %{$self->{'node_info'}}){
            $node_by_id{$self->{'node_info'}->{$node}->{'id'}} = $self->{'node_info'}->{$node};
        }
        $self->{'node_by_id'} = \%node_by_id;

        $self->{'logger'}->info("Updated cache for entire network.");
    } elsif(defined($circuit_id) && $circuit_id != -1) {
        $self->{'logger'}->debug("Updating cache for circuit $circuit_id.");

        my $ckt = $self->get_ckt_object($circuit_id);
        if (!defined $ckt) {
            return &$error("Couldn't create circuit object for circuit $circuit_id");
        }
        $self->{'logger'}->info("Updated cache for circuit $circuit_id.");
    }else{
        $self->{'logger'}->debug("Updating cache for vrf $vrf_id.");

        my $vrf = $self->get_vrf_object($vrf_id);
        if (!defined $vrf) {
            return &$error("Couldn't create vrf object for vrf $vrf_id");
        }

        $vrf->update_vrf_details();
        $self->{'logger'}->info("Updated cache for vrf $vrf_id.");
    }

    # Write the cache to file for our children, then signal children to
    # read updates from file.
    $self->_write_cache();

    my $condvar  = AnyEvent->condvar;
    my $event_id = $self->_generate_unique_event_id();
    $condvar->begin(
        sub {
            $self->{'logger'}->info("Completed sending update_cache to children!");
            return &$success({ status => FWDCTL_SUCCESS, event_id => $event_id });
        }
    );

    foreach my $id (keys %{$self->{'children'}}){
        if (defined $node_id && $node_id != $id) {
            next;
        }
        my $addr = $self->{'node_by_id'}->{$id}->{'mgmt_addr'};
        $condvar->begin();

        $self->{'fwdctl_events'}->{'topic'} = "MPLS.FWDCTL.Switch.$addr";
        $self->{'fwdctl_events'}->update_cache(
            async_callback => sub {
                my $result = shift;
                $condvar->end();
            }
        );
    }
    $condvar->end();
}

=head2 check_child_status

    sends an echo request to the child

=cut
sub check_child_status{
    my $self = shift;

    $self->{'logger'}->info("Checking the status of all children.");
    my $event_id = $self->_generate_unique_event_id();

    foreach my $id (keys %{$self->{'children'}}){
        $self->{'logger'}->debug("Checking status of child: " . $id);
        $self->send_message_to_child($id, {action => 'echo'}, $event_id);
    }

    return {status => 1, event_id => $event_id};
}

=head2 reap_old_events

=cut
sub reap_old_events{
    my $self = shift;

    my $time = time();
    foreach my $event (keys (%{$self->{'pending_events'}})){
        if($self->{'pending_events'}->{$event}->{'ts'} + TIMEOUT > $time){
            delete $self->{'pending_events'}->{$event};
        }
    }
}


=head2 send_message_to_child

send a message to a child

=cut
sub send_message_to_child{
    my $self = shift;
    my $id = shift;
    my $message = shift;
    my $event_id = shift;

    if (!defined $self->{'children'}->{$id}) {
	$self->{'children'}->{$id} = {};
    }
    my $rpc    = $self->{'children'}->{$id}->{'rpc'};
    if(!defined($rpc)){
        $self->{'logger'}->error("No RPC exists for node_id: " . $id);
	$self->make_baby($id);
        $rpc = $self->{'children'}->{$id}->{'rpc'};
    }

    if(!defined($rpc)){
        $self->{'logger'}->error("OMG I couldn't create babies!!!!");
        return;
    }

    $message->{'async_callback'} = $self->message_callback($id, $event_id);
    my $method_name = $message->{'action'};
    delete $message->{'action'};

    $self->{'fwdctl_events'}->{'topic'} = "MPLS.FWDCTL.Switch." . $self->{'node_by_id'}->{$id}->{'mgmt_addr'};
    $self->{'logger'}->info("Sending message to topic: " . $self->{'fwdctl_events'}->{'topic'} . "." . $method_name);
    $self->{'fwdctl_events'}->$method_name( %$message );

    $self->{'pending_results'}->{$event_id}->{'ts'} = time();
    $self->{'pending_results'}->{$event_id}->{'ids'}->{$id} = FWDCTL_WAITING;
}


=head2 addVrf

=cut
sub addVrf{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $success = $m_ref->{'success_callback'};
    my $error = $m_ref->{'error_callback'};

    my $vrf_id = $p_ref->{'vrf_id'}{'value'};

    $self->{'logger'}->error("addVrf: VRF ID required") && $self->{'logger'}->logconfess() if(!defined($vrf_id));
    $self->{'logger'}->info("addVrf: MPLS addVrf: $vrf_id");

    my $vrf = OESS::VRF->new(vrf_id => $vrf_id, db => $self->{'db2'});
    if (!defined $vrf) {
        my $err = "Unable to load VRF $vrf_id.";
        $self->{'logger'}->error($err);
        return &$error($err);
    }
    $vrf->load_endpoints;
    foreach my $ep (@{$vrf->endpoints}) {
        $ep->load_peers;
    }
    $vrf->load_users;
    $vrf->load_workgroup;

    if ($vrf->state eq 'decom') {
        my $err = "addVrf: Adding a decom'd vrf is not allowed";
        $self->{'logger'}->error($err);
        return &$error($err);
    }

    # Ensure local cache is updated with latest VRF.
    $self->{vrfs}->{$vrf_id} = $vrf;
    $self->_write_cache();

    my %nodes;
    foreach my $ep (@{$vrf->endpoints}) {
        $self->{'logger'}->debug("EP: " . Dumper($ep));
        $self->{'logger'}->info("addVrf: Node: " . $ep->node() . " is involved in the vrf");
        $nodes{$ep->node()} = 1;
    }

    my $result = FWDCTL_SUCCESS;

    if ($vrf->state() eq "deploying" || $vrf->state() eq "scheduled") {
        $self->{'logger'}->error("addVrf: Wrong circuit state was encountered");

        my $state = $vrf->state();
        $self->{'logger'}->error($self->{'db2'}->get_error());
    }


    $self->{'logger'}->info("Provisioning L3VPN $vrf_id.");

    my $cv = AnyEvent->condvar;
    my $node_errors = {};

    $cv->begin(
        sub {
            if (!%$node_errors) {
                $self->{'logger'}->info("L3VPN successfully provisioned.");
                return &$success({status => $result});
            }

            foreach my $node (keys %nodes) {
                if (exists $node_errors->{$node}) {
                    # Addition failed so no need to rollback.
                    $self->{logger}->error($node_errors->{$node});
                    next;
                }

                my $node_id = $self->{'node_info'}->{$node}->{'id'};
                my $node_ip = $self->{'node_by_id'}->{$node_id}->{'mgmt_addr'};

                $self->{'fwdctl_events'}->{'topic'} = "MPLS.FWDCTL.Switch.$node_ip";
                $self->{'fwdctl_events'}->remove_vrf(
                    vrf_id => $vrf_id,
                    async_callback => sub {
                        $self->{logger}->warn("Rolled back L3VPN on $node ($node_ip).");
                    });
            }

            return &$error("Failed to provision L3VPN.");
        }
    );

    foreach my $node (keys %nodes){
        $cv->begin();
        $self->{'logger'}->info("Adding VRF " . $vrf->vrf_id() . " to $node.");

        my $node_id = $self->{'node_info'}->{$node}->{'id'};
        my $node_ip = $self->{'node_by_id'}->{$node_id}->{'mgmt_addr'};

        $self->{'fwdctl_events'}->{'topic'} = "MPLS.FWDCTL.Switch.$node_ip";
        $self->{'fwdctl_events'}->add_vrf(
            vrf_id         => $vrf_id,
            async_callback => sub {
                my $res = shift;

                if ($res->{'results'}->{'status'} != FWDCTL_SUCCESS) {
                    $node_errors->{$node} = "Failed to add L3VPN on $node ($node_ip).";
                }
                $cv->end();
            });
    }

    $cv->end();
}

=head2 delVrf

=cut
sub delVrf{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    my $state_ref = shift;

    my $success = $m_ref->{'success_callback'};
    my $error = $m_ref->{'error_callback'};

    my $vrf_id = $p_ref->{'vrf_id'}{'value'};

    $self->{'logger'}->error("delVrf: VRF ID required") && $self->{'logger'}->logconfess() if(!defined($vrf_id));
    $self->{'logger'}->info("Removing VRF $vrf_id.");

    my $vrf = OESS::VRF->new(vrf_id => $vrf_id, db => $self->{'db2'});
    if (!defined $vrf) {
        my $err = "Unable to load VRF $vrf_id.";
        $self->{'logger'}->error($err);
        return &$error($err);
    }
    $vrf->load_endpoints;
    foreach my $ep (@{$vrf->endpoints}) {
        $ep->load_peers;
    }
    $vrf->load_users;
    $vrf->load_workgroup;

    if ($vrf->state eq 'decom') {
        my $err = "delVrf: Removing a decom'd vrf is not allowed";
        $self->{'logger'}->error($err);
        return &$error($err);
    }

    $self->{vrfs}->{$vrf_id} = $vrf;
    $self->_write_cache();

    my %nodes;
    foreach my $ep (@{$vrf->endpoints}) {
        $self->{'logger'}->debug("EP: " . Dumper($ep));
        $self->{'logger'}->debug("delVrf: Node: " . $ep->node . " is involved in the vrf");
        $nodes{$ep->node}= 1;
    }

    my $result = FWDCTL_SUCCESS;

    if ($vrf->state() eq "deploying" || $vrf->state() eq "scheduled") {
        $self->{'logger'}->error("delVrf: Wrong circuit state was encountered");

        my $state = $vrf->state();
        $self->{'logger'}->error($self->{'db2'}->get_error());
    }


    $self->{'logger'}->info("Removing L3VPN $vrf_id.");

    my $cv  = AnyEvent->condvar;
    my $err = '';

    $cv->begin( sub {
        if ($err ne '') {
            $self->{'logger'}->error("Failed to remove VRF: $err");
            return &$error($err);
        }

        $self->{'logger'}->info("Removed VRF.");
        return &$success({status => $result});
    });

    foreach my $node (keys %nodes){
        $cv->begin();

        $self->{'logger'}->error("Getting ready to remove VRF: " . $vrf->vrf_id() . " to switch: " . $node);

        my $node_id = $self->{'node_info'}->{$node}->{'id'};

        $self->{'fwdctl_events'}->{'topic'} = "MPLS.FWDCTL.Switch." . $self->{'node_by_id'}->{$node_id}->{'mgmt_addr'};
        $self->{'fwdctl_events'}->remove_vrf(
            vrf_id => $vrf_id,
            async_callback => sub {
                my $res = shift;

                if($res->{'results'}->{'status'} != FWDCTL_SUCCESS){
                    $self->{'logger'}->error("Switch " . $self->{'node_by_id'}->{$node_id}->{'mgmt_addr'} . " reported an error.");
                    $err .= "Switch " . $self->{'node_by_id'}->{$node_id}->{'mgmt_addr'} . " reported an error. ";
                }
                $cv->end();
            });
    }

    $cv->end();
}

=head2 addVlan

adds a vlan via MPLS

=cut
sub addVlan{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    my $state_ref = shift;
    
    $self->{'logger'}->error("addVlan: Creating Circuit!");

    my $success = $m_ref->{'success_callback'};
    my $error = $m_ref->{'error_callback'};

    my $circuit_id = $p_ref->{'circuit_id'}{'value'};

    $self->{'logger'}->error("addVlan: Circuit ID required") && $self->{'logger'}->logconfess() if(!defined($circuit_id));
    $self->{'logger'}->info("addVlan: MPLS addVlan: $circuit_id");

    my $ckt = $self->get_ckt_object( $circuit_id );
    if(!defined($ckt)){
        my $err = "addVlan: Couldn't load circuit object";
        $self->{'logger'}->error($err);
        return &$error($err);
    }

    if($ckt->{'details'}->{'state'} eq 'decom'){
        my $err = "addVlan: Adding a decom'd circuit is not allowed";
        $self->{'logger'}->error($err);
        return &$error($err);
    }

    if($ckt->{type} ne 'mpls'){
        my $err = "addVlan: Circuit type 'opeflow' cannot be used here";
        $self->{'logger'}->error($err);
        return &$error($err);
    }

    $self->_write_cache();

    #get all the DPIDs involved and remove the flows
    my $endpoints = $ckt->endpoints();
    my %nodes;
    foreach my $ep (@$endpoints){
	$self->{'logger'}->debug("addVlan: Node: " . $ep->{'node'} . " is involved int he circuit");
	$nodes{$ep->{'node'}}= 1;
    }

    my $result = FWDCTL_SUCCESS;

    my $details = $self->{'db'}->get_circuit_details(circuit_id => $circuit_id);
    if ($details->{'state'} eq "deploying" || $details->{'state'} eq "scheduled") {
	$self->{'logger'}->error("addVlan: Wrong circuit state was encountered");

        my $state = $details->{'state'};
	$self->{'logger'}->error($self->{'db'}->get_error());
    }

    #TODO: WHY IS THERE HERE??? Seems like we can remove this...
    $self->{'db'}->update_circuit_path_state(circuit_id  => $circuit_id,
                                             old_state   => 'deploying',
                                             new_state   => 'active');
    
    $self->{'circuit_status'}->{$circuit_id} = OESS_CIRCUIT_UP;

    $self->{'logger'}->info("Adding VLAN.");

    my $cv  = AnyEvent->condvar;
    my $err = '';

    $cv->begin( sub {
        if ($err ne '') {
            foreach my $node (keys %nodes){
                my $node_id = $self->{'node_info'}->{$node}->{'id'};
                my $node_addr = $self->{'node_by_id'}->{$node_id}->{'mgmt_addr'};

                $self->{'fwdctl_events'}->{'topic'} = "MPLS.FWDCTL.Switch." . $node_addr;
                $self->{'fwdctl_events'}->remove_vlan(circuit_id => $circuit_id,
						      async_callback => sub {
							  $self->{'logger'}->error("Removed MPLS circuit from $node_addr.");
						      });
            }
	    
            $self->{'logger'}->error("Failed to add MPLS VLAN.");
            return &$error($err);
        }

        $self->{'logger'}->info("Added VLAN.");
        return &$success({status => $result});
    });

    foreach my $node (keys %nodes){
        $cv->begin();

        my $node_id = $self->{'node_info'}->{$node}->{'id'};

        $self->{'fwdctl_events'}->{'topic'} = "MPLS.FWDCTL.Switch." . $self->{'node_by_id'}->{$node_id}->{'mgmt_addr'};
        $self->{'fwdctl_events'}->add_vlan(
            circuit_id => $circuit_id,
            async_callback => sub {
                my $res = shift;

		if($res->{'results'}->{'status'} != FWDCTL_SUCCESS){
		    $self->{'logger'}->error("Switch " . $self->{'node_by_id'}->{$node_id}->{'mgmt_addr'} . " reported an error.");
		    $err .= "Switch : " . $self->{'node_by_id'}->{$node_id}->{'mgmt_addr'} . " reported an error";
		}
                $cv->end();
            });
    }

    $cv->end();
}

=head2 deleteVlan

deletes a vlan in MPLS mode

=cut
sub deleteVlan{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    my $state_ref = shift;

    my $success = $m_ref->{'success_callback'};
    my $error = $m_ref->{'error_callback'};

    my $circuit_id = $p_ref->{'circuit_id'}{'value'};

    $self->{'logger'}->error("Circuit ID required") && $self->{'logger'}->logconfess() if(!defined($circuit_id));
    $self->{'logger'}->info("Removing Circuit $circuit_id.");

    my $ckt = $self->get_ckt_object( $circuit_id );
    my $event_id = $self->_generate_unique_event_id();
    if(!defined($ckt)){
        return &$error({status => FWDCTL_FAILURE});
    }

    if($ckt->{'details'}->{'state'} eq 'decom'){
        return &$error("Circuit is already decom'd");
    }
    
    #update the cache
    $self->_write_cache();

    #get all the DPIDs involved and remove the flows
    my $endpoints = $ckt->endpoints();
    my %nodes;
    foreach my $ep (@$endpoints){
        $self->{'logger'}->debug("Node: " . $ep->{'node'} . " is involved in the circuit");
        $nodes{$ep->{'node'}}= 1;
    }

    $self->{'logger'}->info("Deleting VLAN.");

    my $cv  = AnyEvent->condvar;
    my $err = '';

    $cv->begin(sub {
        if ($err ne '') {
            $self->{'logger'}->error("Failed to delete MPLS VLAN.");
            return &$error($err);
        }

        delete $self->{'circuit'}->{$circuit_id};
        $self->{'logger'}->info("Deleted VLAN.");
        return &$success({status => FWDCTL_SUCCESS});
    });

    foreach my $node (keys %nodes){
        $cv->begin();

        my $node_id = $self->{'node_info'}->{$node}->{'id'};
        my $node_addr = $self->{'node_by_id'}->{$node_id}->{'mgmt_addr'};

        $self->{'logger'}->info("Sending deleteVLAN to child: " . $node_addr);

        $self->{'fwdctl_events'}->{'topic'} = "MPLS.FWDCTL.Switch." . $node_addr;
        $self->{'fwdctl_events'}->remove_vlan(
            circuit_id => $circuit_id,
            async_callback => sub {
                my $res = shift;

		if( $res->{'results'}->{'status'} != FWDCTL_SUCCESS){
		    my $error = "Switch $node_addr reported an error";
		    $self->{'logger'}->error(Dumper($res));
		    $self->{'logger'}->error($error);
                    $err .= $error . "\n";
		}
                $cv->end();
            });
    }

    $cv->end();
}

=head2 diff

Signals all children to re-read from cache, determine if a
configuration change is required, and if so, make the change.

=cut

sub diff {
    my $self = shift;

    $self->{'logger'}->info("Signaling MPLS nodes to begin diff.");

    foreach my $node_id (keys %{$self->{'children'}}) {
        my $node         = $self->{'db'}->get_node_by_id(node_id => $node_id);
        my $force_diff   = 0;
        my $pending_diff = int($node->{'pending_diff'});

        # If the database asserts a diff is pending we are still waiting
        # for admin approval. Skip diffing for now.


        # If the database asserts there is no diff pending but memory
        # disagrees, then the pending state was modified by an admin.
        # The pending diff may now proceed.
        if ($self->{'children'}->{$node_id}->{'pending_diff'} == PENDING_DIFF && $pending_diff == PENDING_DIFF_NONE) {
            $force_diff = 1;
            $self->{'children'}->{$node_id}->{'pending_diff'} = PENDING_DIFF_NONE;
        }

        $self->{'fwdctl_events'}->{'topic'} = "MPLS.FWDCTL.Switch." . $self->{'node_by_id'}->{$node_id}->{'mgmt_addr'};
        $self->{'fwdctl_events'}->diff(
            force_diff     => $force_diff,
            async_callback => sub {
                my $res = shift;

                if (defined $res->{'error'}) {
                    my $addr = $node->{'mgmt_addr'};
                    my $err = $res->{'error'};
                    $self->{'logger'}->error("Error calling diff on $addr: $err");
                    return 0;
                }

                if ($res->{'results'}->{'status'} == FWDCTL_BLOCKED) {
                    my $node_id = $res->{'results'}->{'node_id'};

                    $self->{'db'}->set_pending_diff(PENDING_DIFF, $node_id);
                    $self->{'children'}->{$node_id}->{'pending_diff'} = PENDING_DIFF;

                    $self->{'logger'}->warn("Diff for node $node_id requires admin approval.");
                    return 0;
                } elsif ($res->{'results'}->{'status'} == FWDCTL_FAILURE) {
                    $self->{db}->set_pending_diff(PENDING_DIFF_ERROR, $node_id);
                    $self->{'children'}->{$node_id}->{'pending_diff'} = PENDING_DIFF_ERROR;

                    $self->{'logger'}->warn("Diff for node $node_id failed.");
                    return 0;
                } else {
                    $self->{'db'}->set_pending_diff(PENDING_DIFF_NONE, $node_id);
                    $self->{'children'}->{$node_id}->{'pending_diff'} = PENDING_DIFF_NONE;

                    return 1;
                }
            });
    }

    return 1;
}

=head2 get_diff_text

returns the diff text for a given node

=cut

sub get_diff_text {
    my $self  = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    $self->{'logger'}->debug("Calling FWDCTL.get_diff_text");

    my $success_cb = $m_ref->{'success_callback'};
    my $error_cb = $m_ref->{'error_callback'};

    my $node_id = $p_ref->{'node_id'}{'value'};
    my $node = $self->{'children'}->{$node_id};
    if (!defined $node) {
        my $err = "Node $node_id doesn't exist.";
        $self->{'logger'}->error($err);
        return &$error_cb($err);
    }

    $self->{'fwdctl_events'}->{'topic'} = "MPLS.FWDCTL.Switch." . $self->{'node_by_id'}->{$node_id}->{'mgmt_addr'};
    $self->{'fwdctl_events'}->get_diff_text(
        async_callback => sub {
            my $response = shift;
            if (defined $response->{'error'}) {
                return &$error_cb($response->{error});
            } else {
                return &$success_cb($response->{results});
            }
        }
    );
}

=head2 get_vrf_object

=cut
sub get_vrf_object{
    my $self = shift;
    my $vrf_id = shift;

    my $vrf = $self->{'vrfs'}->{$vrf_id};
    if (!defined $vrf) {
        $vrf = OESS::VRF->new(vrf_id => $vrf_id, db => $self->{'db2'});
        if (!defined $vrf) {
            $self->{'logger'}->error("Unable to create VRF Object for VRF: " . $vrf_id);
            return;
        }
        $vrf->load_endpoints;
        foreach my $ep (@{$vrf->endpoints}) {
            $ep->load_peers;
        }
        $vrf->load_users;
        $vrf->load_workgroup;

        $self->{'vrfs'}->{$vrf->vrf_id()} = $vrf;
    }

    return $vrf;
}


=head2 get_ckt_object

returns a ckt object for the requested circuit

=cut

sub get_ckt_object{
    my $self =shift;
    my $ckt_id = shift;

    my $ckt = OESS::L2Circuit->new(circuit_id => $ckt_id, db => $self->{'db2'});
    if (!defined $ckt) {
        $self->{'logger'}->error("Error occured creating circuit: " . $ckt_id);
        return;
    }

    if ($ckt->{'type'} ne 'mpls') {
        $self->{'logger'}->error("Circuit $ckt_id is not of type MPLS.");
        return undef;
    }

    $ckt->load_endpoints;
    $ckt->load_paths;
    $self->{'circuit'}->{$ckt->circuit_id} = $ckt;

    return $ckt;
}

=head2 message_callback

sends a message and puts the response in a pending results queue

=cut

sub message_callback {
    my $self     = shift;
    my $id     = shift;
    my $event_id = shift;

    return sub {
        my $results = shift;
        $self->{'logger'}->debug("Received a response from child: " . $id . " for event: " . $event_id . " Dumper: " . Data::Dumper::Dumper($results));
        $self->{'pending_results'}->{$event_id}->{'ids'}->{$id} = FWDCTL_UNKNOWN;
        if (!defined $results) {
            $self->{'logger'}->error("Undefined result received in message_callback.");
        } elsif (defined $results->{'error'}) {
            $self->{'logger'}->error($results->{'error'});
        }

        $self->{'node_rules'}->{$id} = $results->{'results'}->{'total_rules'};
	$self->{'logger'}->debug("Event: $event_id for ID: " . $event_id . " status: " . $results->{'results'}->{'status'});
        $self->{'pending_results'}->{$event_id}->{'ids'}->{$id} = $results->{'results'}->{'status'};
    }
}

sub _generate_unique_event_id{
    my $self = shift;
    return $self->{'uuid'}->to_string($self->{'uuid'}->create());
}

=head2 get_event_status

gives us the current status of a requested event
I don't believe this is used anymore!

=cut

sub get_event_status{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    my $state = shift;

    my $event_id = $p_ref->{'event_id'}->{'value'};

    $self->{'logger'}->debug("Looking for event: " . $event_id);
    $self->{'logger'}->debug("Pending Results: " . Data::Dumper::Dumper($self->{'pending_results'}));

    if(defined($self->{'pending_results'}->{$event_id})){
        my $results = $self->{'pending_results'}->{$event_id}->{'ids'};
        
        foreach my $id (keys %{$results}){
            $self->{'logger'}->debug("ID: " . $id . " reports status: " . $results->{$id});
            if($results->{$id} == FWDCTL_WAITING){
                $self->{'logger'}->debug("Event: $event_id id $id reports still waiting");
                return {status => FWDCTL_WAITING};
            }elsif($results->{$id} == FWDCTL_FAILURE){
                $self->{'logger'}->debug("Event : $event_id id $id reports error!");
                return {status => FWDCTL_FAILURE};
            }
        }
        #done waiting and was success!
        $self->{'logger'}->debug("Event $event_id is complete!!");
        return {status => FWDCTL_SUCCESS};
    } elsif (defined $self->{'events'}->{$event_id}) {

        my $event = $self->{'events'}->{$event_id};
        if ($event->{'status'} != FWDCTL_WAITING) {
            delete $self->{'events'}->{$event_id};
        }
        return $event;

    } else {
        #no known event by that ID
        return {status => FWDCTL_UNKNOWN};
    }
}

=head2 save_mpls_nodes_status

save_mpls_nodes_status gets the current connection status of all
active mpls nodes, and saves them in the database.

=cut
sub save_mpls_nodes_status {
    my $self = shift;

    my $nodes = $self->{'db'}->get_current_nodes(type => 'mpls');
    foreach my $node (@{$nodes}) {
        $self->{'fwdctl_events'}->{'topic'} = 'MPLS.FWDCTL.Switch.' . $node->{'mgmt_addr'};

        $self->{'fwdctl_events'}->is_connected(
            async_callback => sub {
                my $result = shift;
                if (!defined $result) {
                    $self->{'logger'}->error("Cannot get MPLS node $node->{'node_id'} status; Setting status to 'down'.");
                    return $self->{'db'}->set_mpls_node_status($node->{'node_id'}, 'down');
                }
                if (defined $result->{'error'}) {
                    $self->{'logger'}->error("MPLS node $node->{'node_id'} error: $result->{'error'}. Setting status to 'down'.");
                    return $self->{'db'}->set_mpls_node_status($node->{'node_id'}, 'down');
                }

                if (int($result->{'results'}->{'connected'}) == 0) {
                    $self->{'logger'}->info("Setting MPLS node $node->{'node_id'} status to 'down'.");
                    return $self->{'db'}->set_mpls_node_status($node->{'node_id'}, 'down');
                }

                $self->{'logger'}->info("Setting MPLS node $node->{'node_id'} status to 'up'.");
                return $self->{'db'}->set_mpls_node_status($node->{'node_id'}, 'up');
        });
    }

    $self->{'fwdctl_events'}->{'topic'} = 'MPLS.FWDCTL.event';
}

=head2 echo

Always returns 1.

=cut
sub echo {
    my $self = shift;
    return {status => 1};
}

=head2 stop

Sends a shutdown signal on MPLS.FWDCTL.event.stop. Child processes
should listen for this signal and cleanly exit when received.

=cut
sub stop {
    my $self = shift;

    $self->{'logger'}->info("Sending MPLS.FWDCTL.event.stop to listeners");
    $self->{'fwdctl_events'}->{'topic'} = "MPLS.FWDCTL.Switch";
    $self->{'fwdctl_events'}->stop( no_reply => 1);

    $self->{'fwdctl_dispatcher'}->stop_consuming();
}

1;
