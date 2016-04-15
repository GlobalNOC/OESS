use strict;
use warnings;

###############################################################################
package OESS::MPLS::FWDCTL;

use Socket;

use OESS::Database;
use OESS::Topology;
use OESS::Circuit;

#anyevent
use AnyEvent;
use AnyEvent::Fork;

use GRNOC::RabbitMQ::Client;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

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

=cut

sub new {
    my $class = shift;
    my %params = @_;
    my $self = \%params;
    bless $self, $class;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.FWDCTL.MASTER');

    if(!defined($self->{'config'})){
        $self->{'config'} = "/etc/oess/database.xml";
    }

    $self->{'db'} = OESS::Database->new( config_file => $self->{'config'} );

    my $fwdctl_dispatcher = GRNOC::RabbitMQ::Dispatcher->new( host => $self->{'db'}->{'rabbitMQ'}->{'host'},
                                                              port => $self->{'db'}->{'rabbitMQ'}->{'port'},
                                                              user => $self->{'db'}->{'rabbitMQ'}->{'user'},
                                                              pass => $self->{'db'}->{'rabbitMQ'}->{'pass'},
                                                              exchange => 'OESS',
                                                              queue => 'MPLS-FWDCTL',
                                                              topic => "MPLS.FWDCTL.RPC");

    $self->register_rpc_methods( $fwdctl_dispatcher );

    $self->{'fwdctl_dispatcher'} = $fwdctl_dispatcher;


    $self->{'fwdctl_events'} = GRNOC::RabbitMQ::Client->new( host => $self->{'db'}->{'rabbitMQ'}->{'host'},
                                                             port => $self->{'db'}->{'rabbitMQ'}->{'port'},
                                                             user => $self->{'db'}->{'rabbitMQ'}->{'user'},
                                                             pass => $self->{'db'}->{'rabbitMQ'}->{'pass'},
                                                             exchange => 'OESS',
                                                             topic => 'MPLS.FWDCTL.event');



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

    $self->update_cache(-1);

    #from TOPO startup
    my $nodes = $self->{'db'}->get_current_nodes( mpls => 1);
    foreach my $node (@$nodes) {
	$self->make_baby($node->{'node_id'});
    }

    
    $self->{'logger'}->error("MPLS Provisioner INIT COMPLETE");

    
    
    return $self;
}

sub populate_devices{
    my $self = shift;

    foreach my $node (keys %{$self->{'node_by_id'}}){
	$self->{'fwdctl_events'}->{'topic'} = "MPLS.FWDCTL.Switch." . $self->{'node_by_id'}->{$node}->{'mgmt_addr'};
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

sub build_cache{
    my %params = @_;
    
    
    my $db = $params{'db'};
    my $logger = $params{'logger'};

    die if(!defined($logger));

    #basic assertions
    $logger->error("DB was not defined") && $logger->logcluck() && exit 1 if !defined($db);
    $logger->error("DB Version does not match expected version") && $logger->logcluck() && exit 1 if !$db->compare_versions();
    
    
    $logger->debug("Fetching State from the DB");
    my $circuits = $db->get_current_circuits( mpls => 1, openflow => 0);

    #init our objects
    my %ckts;
    my %circuit_status;
    my %link_status;
    my %node_info;
    foreach my $circuit (@$circuits) {
	next if($circuit->get_type() ne 'mpls');
        my $id = $circuit->{'circuit_id'};
        my $ckt = OESS::Circuit->new( db => $db,
                                      circuit_id => $id );
        $ckts{ $ckt->get_id() } = $ckt;
        
        my $operational_state = $circuit->{'details'}->{'operational_state'};
        if ($operational_state eq 'up') {
            $circuit_status{$id} = OESS_CIRCUIT_UP;
        } elsif ($operational_state  eq 'down') {
            $circuit_status{$id} = OESS_CIRCUIT_DOWN;
        } else {
            $circuit_status{$id} = OESS_CIRCUIT_UNKNOWN;
        }
    }
        
    my $links = $db->get_current_links();
    foreach my $link (@$links) {
        if ($link->{'status'} eq 'up') {
            $link_status{$link->{'name'}} = OESS_LINK_UP;
        } elsif ($link->{'status'} eq 'down') {
            $link_status{$link->{'name'}} = OESS_LINK_DOWN;
        } else {
            $link_status{$link->{'name'}} = OESS_LINK_UNKNOWN;
        }
    }
        
    my $nodes = $db->get_current_nodes( mpls => 1 );
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
	$node_info{$node->{'name'}} = $details;
    }

    return {ckts => \%ckts, circuit_status => \%circuit_status, link_status => \%link_status, node_info => \%node_info};

}

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

    my %switches;

    foreach my $ckt_id (keys (%{$self->{'circuit'}})){
        my $found = 0;
        $self->{'logger'}->debug("writing circuit: " . $ckt_id . " to cache");
        
        my $ckt = $self->get_ckt_object($ckt_id);
        if(!defined($ckt)){
            $self->{'logger'}->error("No Circuit could be created or found for circuit: " . $ckt_id);
            next;
        }
        my $details = $ckt->get_details();

	my $eps = $ckt->get_endpoints();


	
#	foreach my $ep (@$eps){	
	for(my $i=0;$i<scalar(@$eps);$i++){

	    my $ep = $eps->[$i];

	    my $dest;
	    if($i == scalar(@{$eps}) -1 ){
		$dest = $self->{'node_info'}->{$eps->[0]->{'node'}}->{'router_ip'};
	    }else{
		$dest = $self->{'node_info'}->{$eps->[$i + 1]->{'node'}}->{'router_ip'};
	    }


	    #generate primary path
	    my $primary_path = [];
	    my $backup_path = [];
	    

	    #generate backup path
	    my $bp;
	    if($ckt->has_backup_path()){
		$bp = $ckt->get_path( path => 'backup');
	    }   

	    my $obj = { circuit_name => $ckt->get_name(),
			interface => $ep->{'interface'},
			vlan_tag => $ep->{'tag'},
			primary_path => $primary_path,
			backup_path => $backup_path,
			destination_ip => $dest
	    };
	    
	    $switches{$ep->{'node'}}->{$details->{'circuit_id'}} = $obj;
	}
    }

    foreach my $node (keys %{$self->{'node_info'}}){
	my $data;
	$data->{'nodes'} = $self->{'node_by_id'};
	$data->{'ckts'} = $switches{$node};
	$self->{'logger'}->info("writing shared file for node_id: " . $self->{'node_info'}->{$node}->{'id'});
	my $file = $self->{'share_file'} . "." . $self->{'node_info'}->{$node}->{'id'};
	open(my $fh, ">", $file) or $self->{'logger'}->error("Unable to open $file " . $!);
        print $fh encode_json($data);
        close($fh);
    }

}


sub register_rpc_methods{
    my $self = shift;
    my $d = shift;

    my $method = GRNOC::RabbitMQ::Method->new( name => "addVlan",
					       callback => sub { $self->addVlan(@_) },
					       description => "adds a VLAN to the network that exists in OESS DB");
    
    $method->add_input_parameter( name => "circuit_id",
				  description => "the circuit ID to add",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::INTEGER);
    
    $d->register_method($method);
    
    $method = GRNOC::RabbitMQ::Method->new( name => "deleteVlan",
					    callback => sub { $self->deleteVlan(@_) },
					    description => "deletes a VLAN to the network that exists in OESS DB");
    
    $method->add_input_parameter( name => "circuit_id",
                                  description => "the circuit ID to delete",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);
    
    $d->register_method($method);
    
    
    $method = GRNOC::RabbitMQ::Method->new( name => 'update_cache',
					    callback => sub { $self->update_cache(@_) },
					    description => 'Updates the circuit cache');

    
    $method->add_input_parameter( name => "circuit_id",
                                  description => "the circuit ID to delete",
                                  required => 1,
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
    
    $method = GRNOC::RabbitMQ::Method->new( name => "new_switch",
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
	next if(!$node->{'mpls'});
	$self->{'logger'}->error("This switch already exists!");
	return FWDCTL_FAILURE;
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
	return FWDCTL_FAILURE;
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
    $logger = Log::Log4perl->get_logger("MPLS.FWDCTL.MASTER");
    $logger->info("Creating child for id: " . $args{"id"});
    $switch = OESS::MPLS::Switch->new( %args );
    }')->fork->send_arg( %args )->run("run");

    $self->{'children'}->{$id}->{'rpc'} = 1;
}


=head2 update_cache
updates the cache for all of the children
=cut

sub update_cache{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    
    my $circuit_id = $p_ref->{'circuit_id'}->{'value'};

    if(!defined($circuit_id) || $circuit_id == -1){
        $self->{'logger'}->debug("Updating Cache for entire network");
        my $res = build_cache(db => $self->{'db'}, logger => $self->{'logger'});
        $self->{'circuit'} = $res->{'ckts'};
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
    }else{
        $self->{'logger'}->debug("Updating cache for circuit: " . $circuit_id);
        my $ckt = $self->get_ckt_object($circuit_id);
        if(!defined($ckt)){
            return {status => FWDCTL_FAILURE, event_id => $self->_generate_unique_event_id()};
        }
        $ckt->update_circuit_details();
        $self->{'logger'}->debug("Updating cache for circuit: " . $circuit_id . " complete");
    }

    #write the cache for our children
    $self->_write_cache();
    my $event_id = $self->_generate_unique_event_id();
    foreach my $child (keys %{$self->{'children'}}){
	$self->send_message_to_child($child,{action => 'update_cache'},$event_id);
    }
    
    $self->{'logger'}->debug("Completed sending message to children!");

    return { status => FWDCTL_SUCCESS, event_id => $event_id };
}

=head2 check_child_status
    sends an echo request to the child
=cut

sub check_child_status{
    my $self = shift;

    $self->{'logger'}->debug("Checking on child status");
    my $event_id = $self->_generate_unique_event_id();
    foreach my $id (keys %{$self->{'children'}}){
        $self->{'logger'}->debug("checking on child: " . $id);
        my $child = $self->{'children'}->{$id};
        my $corr_id = $self->send_message_to_child($id,{action => 'echo'},$event_id);            
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
    $self->{'fwdctl_events'}->$method_name( %$message );

    $self->{'pending_results'}->{$event_id}->{'ts'} = time();
    $self->{'pending_results'}->{$event_id}->{'ids'}->{$id} = FWDCTL_WAITING;
}



sub addVlan{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    my $state_ref = shift;

    my $circuit_id = $p_ref->{'circuit_id'}{'value'};

    $self->{'logger'}->error("Circuit ID required") && $self->{'logger'}->logconfess() if(!defined($circuit_id));
    $self->{'logger'}->info("addVlan: $circuit_id");

    my $event_id = $self->_generate_unique_event_id();

    my $ckt = $self->get_ckt_object( $circuit_id );
    if(!defined($ckt)){
        return {status => FWDCTL_FAILURE, event_id => $event_id};
    }

    $ckt->update_circuit_details();
    if($ckt->{'details'}->{'state'} eq 'decom'){
	return {status => FWDCTL_FAILURE, event_id => $event_id};
    }

    if($ckt->get_type() ne 'mpls'){
	return {status => FWDCTL_FAILURE, event_id => $event_id, msg => "This was not an MPLS Circuit"};
    }

    $self->_write_cache();

    #get all the DPIDs involved and remove the flows
    my $endpoints = $ckt->get_endpoints();
    my %nodes;
    foreach my $ep (@$endpoints){
	$self->{'logger'}->debug("Node: " . $ep->{'node'} . " is involved int he circuit");
	$nodes{$ep->{'node'}}= 1;
    }

    my $result = FWDCTL_SUCCESS;

    my $details = $self->{'db'}->get_circuit_details(circuit_id => $circuit_id);


    if ($details->{'state'} eq "deploying" || $details->{'state'} eq "scheduled") {
        
        my $state = $details->{'state'};
	$self->{'logger'}->error($self->{'db'}->get_error());
    }

    #TODO: WHY IS THERE HERE??? Seems like we can remove this...
    $self->{'db'}->update_circuit_path_state(circuit_id  => $circuit_id,
                                             old_state   => 'deploying',
                                             new_state   => 'active');
    
    $self->{'circuit_status'}->{$circuit_id} = OESS_CIRCUIT_UP;

    foreach my $node (keys %nodes){
	$self->{'logger'}->debug("Sending add VLAN to child: " . $node);
	my $id = $self->{'node_info'}->{$node}->{'id'};
        $self->send_message_to_child($id,{action => 'add_vlan', circuit_id => $circuit_id}, $event_id);
    }


    return {status => $result, event_id => $event_id};
}

sub deleteVlan{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    my $state_ref = shift;

    my $circuit_id = $p_ref->{'circuit_id'}{'value'};

    $self->{'logger'}->error("Circuit ID required") && $self->{'logger'}->logconfess() if(!defined($circuit_id));

    my $ckt = $self->get_ckt_object( $circuit_id );
    my $event_id = $self->_generate_unique_event_id();
    if(!defined($ckt)){
        return {status => FWDCTL_FAILURE, event_id => $event_id};
    }
    
    $ckt->update_circuit_details();

    if($ckt->{'details'}->{'state'} eq 'decom'){
	return {status => FWDCTL_FAILURE, event_id => $event_id};
    }
    
    #update the cache
    $self->_write_cache();

    #get all the DPIDs involved and remove the flows
    my $endpoints = $ckt->get_endpoints();
    my %nodes;
    foreach my $ep (@$endpoints){
        $self->{'logger'}->debug("Node: " . $ep->{'node'} . " is involved int he circuit");
        $nodes{$ep->{'node'}}= 1;
    }

    my $result = FWDCTL_SUCCESS;

    foreach my $node (keys %nodes){
        $self->{'logger'}->debug("Sending deleteVLAN to child: " . $node);
        my $id = $self->{'node_info'}->{$node}->{'id'};
        $self->send_message_to_child($id,{action => 'remove_vlan', circuit_id => $circuit_id}, $event_id);
    }

    return {status => $result, event_id => $event_id};

}



sub get_ckt_object{
    my $self =shift;
    my $ckt_id = shift;
    
    my $ckt = $self->{'circuit'}->{$ckt_id};
    
    if(!defined($ckt)){
        $ckt = OESS::Circuit->new( circuit_id => $ckt_id, db => $self->{'db'});
        
	if(!defined($ckt)){
	    return;
	}
	$self->{'circuit'}->{$ckt->get_id()} = $ckt;
    }
    
    if(!defined($ckt)){
        $self->{'logger'}->error("Error occured creating circuit: " . $ckt_id);
    }

    return $ckt;
}


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
    }else{
        #no known event by that ID
        return {status => FWDCTL_UNKNOWN};
    }
}

=head2 echo
Always returns 1.
=cut
sub echo {
    my $self = shift;
    return {status => 1};
}

=head2 stop
Sends a shutdown signal on OF.FWDCTL.event.stop. Child processes
should listen for this signal and cleanly exit when received.
=cut
sub stop {
    my $self = shift;

    $self->{'logger'}->info("Sending MPLS.FWDCTL.event.stop to listeners");
    $self->{'fwdctl_events'}->{'topic'} = "MPLS.FWDCTL.event";
    $self->{'fwdctl_events'}->stop();
}

1;
