#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Switch;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

use AnyEvent;
use Data::Dumper;
use Log::Log4perl;
use Switch;
use Template;
use Net::Netconf::Manager;

use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Client;
use GRNOC::WebService::Regex;

use OESS::Config;
use OESS::MPLS::Device;
use OESS::MPLS::Device::Juniper::MX;
use OESS::MPLS::Device::Juniper::VXLAN;

use JSON::XS;

=head2 new

=cut
sub new {
    my $class = shift;
    my %args = (
        rabbitMQ_host => undef,
        rabbitMQ_port => undef,
        rabbitMQ_user => undef,
        rabbitMQ_pass => undef,
        use_cache => 1,
        node => undef,
        type => 'unknown', # Used to name switch procs viewed via `ps`
        @_
    );

    my $self = \%args;
    bless $self, $class;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.Switch.' . $self->{'id'});
    $self->{'config'} = $args{'config'} || '/etc/oess/database.xml';
    $self->{'config_obj'} = new OESS::Config(config_filename => $self->{'config'});

    $self->{'node'}->{'node_id'} = $self->{'id'};
    
    if($self->{'use_cache'}){
	$self->_update_cache();
    }

    $0 = "oess_mpls_switch.$self->{type}($self->{node}->{mgmt_addr})";

    $self->create_device_object();
    if(!defined($self->{'device'})){
	$self->{'logger'}->error("Unable to create Device instance!");
	die;
    }
    
    if(!defined($self->{'topic'})){
	$self->{'topic'} = "MPLS.FWDCTL.Switch";
    }

    my $topic = $self->{'topic'} . "." .  $self->{'node'}->{'mgmt_addr'} . "." . $self->{'node'}->{'tcp_port'};
    $self->{'logger'}->error("Listening to topic: " . $topic);

    my $dispatcher = GRNOC::RabbitMQ::Dispatcher->new( host => $args{'rabbitMQ_host'},
                                                       port => $args{'rabbitMQ_port'},
                                                       user => $args{'rabbitMQ_user'},
                                                       pass => $args{'rabbitMQ_pass'},
                                                       topic => $topic,
                                                       exchange => 'OESS',
                                                       exclusive => 1);
    $self->_register_rpc_methods( $dispatcher );

    #attempt to reconnect!
    warn "Setting up reconnect timer\n";
    $self->{'connect_timer'} = AnyEvent->timer(
        after    => 60,
        interval => 60,
        cb => sub {
            if (!$self->{'device'}->connected()) {
                $self->{'logger'}->warn("Device is not connected. Attempting to connect");
                return $self->{'device'}->connect();
            }
        });

    #try and connect up right away
    my $ok = $self->{'device'}->connect();
    if (!$ok) {
        warn "Unable to connect\n";
        $self->{'logger'}->error("Connection to device could not be established.");
    } else {
        $self->{'logger'}->debug("Connection to device was established.");
    }

    $self->{'ckts'} = {};

    AnyEvent->condvar->recv;
    return $self;
}

=head2 set_pending

Sets the in-memory state for a devices diff state. If durring a diff
the in-memory state is 0, but 1 is stored in the database, a diff will
be forced to occur.

=cut
sub set_pending {
    my $self  = shift;
    my $state = shift;

    $self->{'pending_diff'} = $state;
    $self->{'device'}->{'pending_diff'} = $state;
    return 1;
}

=head2 create_device_object

creates the correct device object based on params passed in

=cut

sub create_device_object{
    my $self = shift;

    my $host_info = $self->{'node'};
    $host_info->{'config'} = $self->{'config'};

    switch($host_info->{'vendor'}){
        case "Juniper" {
            my $dev;
            if ($host_info->{'model'} =~ /mx/i || $host_info->{'model'} =~ /qfx/i) {
                if ($self->{'config_obj'}->network_type eq 'evpn-vxlan') {
                    $self->{'logger'}->debug("create_device_object: " . Dumper($host_info));
                    $dev = OESS::MPLS::Device::Juniper::VXLAN->new( %$host_info );
                } else {
                    $self->{'logger'}->debug("create_device_object: " . Dumper($host_info));
                    $dev = OESS::MPLS::Device::Juniper::MX->new( %$host_info );
                }
            } else {
                $self->{'logger'}->error("Juniper " . $host_info->{'model'} . " is not supported");
                return;
            }

            if(!defined($dev)){
                $self->{'logger'}->error("Unable to instantiate Device!");
                return;
            }

            $self->{'device'} = $dev;

        }else{
            $self->{'logger'}->error("Unsupported device type: ");
            return;
        }
    }
}

sub _register_rpc_methods{
    my $self = shift;
    my $dispatcher = shift;

    my $method = GRNOC::RabbitMQ::Method->new( name => "add_vlan",
					       description => "adds a vlan for this switch",
                                               callback => sub { return {status => $self->add_vlan(@_) }});
    
    $method->add_input_parameter( name => "circuit_id",
                                  description => "circuit_id to be added",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NUMBER_ID);
    $dispatcher->register_method($method);


    $method = GRNOC::RabbitMQ::Method->new(
        name => "modify_vlan",
        description => "modify_vlan modifies an existing l2 connection.",
        callback => sub { return { status => $self->modify_vlan(@_) }; }
    );
    $method->add_input_parameter(
        name => "circuit_id",
        description => "ID of l2 connection to be modified.",
        required => 1,
        pattern => $GRNOC::WebService::Regex::NUMBER_ID
    );
    $method->add_input_parameter(
        name => "pending",
        description => "l2 connection hash as it should appear on the network.",
        required => 1,
        pattern => $GRNOC::WebService::Regex::TEXT
    );
    $method->add_input_parameter(
        name => "previous",
        description => "l2 connection hash as it should appear on the network.",
        required => 1,
        pattern => $GRNOC::WebService::Regex::TEXT
    );
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => "remove_vlan",
                                            description => "removes a vlan for this switch",
                                            callback => sub { return {status => $self->remove_vlan(@_) }});

    $method->add_input_parameter( name => "circuit_id",
                                  description => "circuit_id to be removed",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NUMBER_ID);
    $dispatcher->register_method($method);
    
    $method = GRNOC::RabbitMQ::Method->new( name => "add_vrf",
                                            description => "adds a vrf for this switch",
                                            callback => sub { return {status => $self->add_vrf(@_) }});
    
    $method->add_input_parameter( name => "vrf_id",
                                  description => "vrf_id to be added",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NUMBER_ID);
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(
        name => "modify_vrf",
        description => "modify_vrf modifies an existing l3 connection.",
        callback => sub { return { status => $self->modify_vrf(@_) }; }
    );
    $method->add_input_parameter(
        name => "vrf_id",
        description => "ID of l3 connection to be modified.",
        required => 1,
        pattern => $GRNOC::WebService::Regex::NUMBER_ID
    );
    $method->add_input_parameter(
        name => "pending",
        description => "l3 connection hash as it should appear on the network.",
        required => 1,
        pattern => $GRNOC::WebService::Regex::TEXT
    );
    $method->add_input_parameter(
        name => "previous",
        description => "l3 connection hash as it should appear on the network.",
        required => 1,
        pattern => $GRNOC::WebService::Regex::TEXT
    );
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => "remove_vrf",
                                            description => "removes a vrf from this switch",
                                            callback => sub { return {status => $self->remove_vrf(@_) }});

    $method->add_input_parameter( name => "vrf_id",
                                  description => "vrf_id to be removed",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NUMBER_ID);
    $dispatcher->register_method($method);


    $method = GRNOC::RabbitMQ::Method->new( name => "echo",
                                            description => " just an echo to check to see if we are aliave",
                                            callback => sub { return {status => 1, msg => "I'm alive!"}});
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => "force_sync",
                                            description => " handle force_sync event",
                                            callback => sub { $self->{'logger'}->warn("received a force_sync command");
                                                              $self->_update_cache();
                                                              $self->{'needs_diff'} = time();
                                                              return {status => 1, msg => "diff scheduled!"}; });
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => "update_cache",
                                            description => " handle thes update cahce call",
                                            callback => sub { $self->_update_cache();
                                                              return {status => 1, msg => "cache updated"}});
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name        => "stop",
                                            callback    => sub {
                                                $self->stop();
                                            },
                                            description => "Notification that FWDCTL/Discovery has exited",
                                            topic => $self->{'topic'});
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name        => "get_interfaces",
                                            callback    => sub {
                                                $self->get_interfaces();
                                            },
                                            description => "returns a list of interfaces on the device");
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name        => "get_routed_lsps",
                                            callback    => sub {
                                                $self->get_routed_lsps(@_);
                                            },
                                            description => "returns the LSPs (in a given routing table) that originate on the device");

    $method->add_input_parameter( name => "table",
                                  description => "The routing table to look for LSPs in",
                                  required => 1,
                                  schema => { type => 'string' });

    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name        => "get_isis_adjacencies",
                                            callback    => sub {
                                                $self->get_isis_adjacencies();
                                            },
                                            description => "returns a list of IS-IS adjacencies from this switch");
    $dispatcher->register_method($method);


    $method = GRNOC::RabbitMQ::Method->new( name        => "get_LSPs",
                                            callback    => sub {
                                                $self->get_LSPs();
                                            },
                                            description => "returns a list of LSPs and their details");
    $dispatcher->register_method($method);


    $method = GRNOC::RabbitMQ::Method->new( name        => "get_lsp_paths",
                                            callback    => sub {
                                                $self->get_lsp_paths(@_);
                                            },
                                            description => "for each LSP on the switch, provides a list of link addresses",
                                            async => 1);
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => "get_vrf_stats",
                                            callback => sub {
                                                $self->get_vrf_stats(@_);
                                            },
                                            description => "Get VRF BGP Stats",
                                            async => 1);

    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name        => "is_connected",
                                            callback    => sub {
                                                return $self->connected();
                                            },
                                            description => "returns the current connected state of the device");
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(
        name        => "get_system_info",
        async       => 1,
        callback    => sub { $self->get_system_info(@_); },
        description => "returns the system information"
    );
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name        => "diff",
					    callback    => sub {
                                                my $node_id = $self->{'node'}->{'node_id'};
                                                my $status  = $self->diff(@_);
                                                return { node_id => $node_id, status  => $status };
                                            },
					    description => "Proxies diff signal to the underlying device object.");
    $method->add_input_parameter( name => "force_diff",
                                  description => "Set to 1 if size of diff should be ignored",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(
        name        => "get_diff_text",
        async       => 1,
        callback    => sub { $self->get_diff_text(@_); },
        description => "Proxies diff signal to the underlying device object."
    );
    $dispatcher->register_method($method);
}

sub _update_cache {
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    $self->{'logger'}->debug("Loading cache from $self->{'share_file'}");

    if (!-e $self->{'share_file'}) {
        $self->{'logger'}->error("Cache file $self->{'share_file'} doesn't exists!");
        return;
    }

    open(my $fh, "<", $self->{'share_file'}) or do {
        $self->{'logger'}->error("Could not open $self->{'share_file'}");
        return;
    };

    my $str = '';
    while(my $line = <$fh>){
        $str .= $line;
    }

    close($fh) or do {
        $self->{'logger'}->error("Could not close $self->{'share_file'}");
        return;
    };

    my $data = eval { decode_json($str) };
    if ($@) {
        $self->{'logger'}->error("Could not decode cache file: $@");
        return;
    }

    $self->{'logger'}->debug("Loading cache file into memory: " . Dumper($data));
    $self->{'node'}     = $data->{'nodes'}->{$self->{'id'}};
    $self->{'settings'} = $data->{'settings'};

    foreach my $ckt (keys %{$self->{'ckts'}}) {
        delete $self->{'ckts'}->{$ckt};
    }

    foreach my $ckt (keys %{$data->{'ckts'}}) {
        $self->{'logger'}->debug("Processing cache for circuit $ckt");

        $data->{'ckts'}->{$ckt}->{'circuit_id'} = $ckt;
        $self->{'ckts'}->{$ckt} = $data->{'ckts'}->{$ckt};
    }

    foreach my $vrf (keys %{$self->{'vrfs'}}){
        delete $self->{'vrfs'}->{$vrf};
    }

    foreach my $vrf (keys %{$data->{'vrfs'}}) {
        $self->{'logger'}->debug("Processing cache for vrf $vrf");

        $data->{'vrfs'}->{$vrf}->{'vrf_id'} = $vrf;
        $self->{'vrfs'}->{$vrf} = $data->{'vrfs'}->{$vrf};
    }

    if ($self->{'node'}->{'name'}) {
        $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.FWDCTL.Switch.'.$self->{'node'}->{'name'});

        # If a node name changes its important we update it. Failure
        # to do so will cause diff to re-add any sites with the old
        # node name.
        $self->{'device'}->{'name'} = $self->{'node'}->{'name'};
    }

    $self->{'logger'}->info("Loaded cache from $self->{'share_file'}");
    return 1;
}

=head2 echo

Always returns 1.

=cut
sub echo {
    my $self = shift;
    return {status => 1};
}

=head2 connected

=cut

sub connected{
    my $self = shift;
    
    return {connected => $self->{'device'}->connected()};
}

=head2 stop

Sends a shutdown signal on OF.FWDCTL.event.stop. Child processes
should listen for this signal and cleanly exit when received.

=cut
sub stop {
    my $self = shift;
    $self->{'logger'}->info("FWDCTL has stopped; Now exiting.");

    exit 0;
}

=head2 add_vlan

Adds a VLAN to this switch

=cut
sub add_vlan{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $circuit = $p_ref->{'circuit_id'}{'value'};

    $self->{'logger'}->debug("Calling add_vlan: " . $circuit);

    $self->_update_cache();
    
    my $vlan_obj = $self->_generate_commands( $circuit );

    return $self->{'device'}->add_vlan($vlan_obj);
}

=head2 modify_vlan

=cut
sub modify_vlan {
    my $self = shift;
    my $method = shift;
    my $params = shift;

    my $circuit_id = $params->{circuit_id}{value};
    my $pending = decode_json($params->{pending}{value});
    my $previous = decode_json($params->{previous}{value});

    # Lookup circuit type from cached circuit
    # my $vlan_obj = $self->_generate_commands($circuit_id);
    # $pending->{ckt_type} = $vlan_obj->{ckt_type}
    # $previous->{ckt_type} = $vlan_obj->{ckt_type}

    $self->{logger}->debug("Calling modify_vlan: $circuit_id");
    return $self->{device}->modify_vlan($previous, $pending);
}

=head2 get_system_info

=cut
sub get_system_info {
    my $self = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{'success_callback'};
    my $error   = $method->{'error_callback'};

    my ($info, $err) = $self->{'device'}->get_system_information();
    if (defined $err) {
        $self->{'logger'}->error($err);
        return &$error($err);
    }
    return &$success($info);
}


=head2 remove_vlan

removes a VLAN from this switch

=cut
sub remove_vlan{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $circuit = $p_ref->{'circuit_id'}{'value'};

    $self->{'logger'}->debug("Calling remove_vlan: " . $circuit);

    $self->_update_cache();

    my $vlan_obj = $self->_generate_commands( $circuit );

    my $res = $self->{'device'}->remove_vlan($vlan_obj);
    $self->{'logger'}->debug("after remove vlan");
    $self->{'logger'}->debug("Results: " . Data::Dumper::Dumper($res));
    return $res;
}

=head2 add_vrf

adds a VRF to the device

=cut
sub add_vrf{

    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $vrf = $p_ref->{'vrf_id'}{'value'};

    $self->{'logger'}->error("Calling add_vrf: " . $vrf);

    $self->_update_cache();

    my $vrf_obj = $self->_generate_vrf_commands( $vrf );

    return $self->{'device'}->add_vrf($vrf_obj);
}

=head2 modify_vrf

=cut
sub modify_vrf {
    my $self = shift;
    my $method = shift;
    my $params = shift;

    my $vrf_id = $params->{vrf_id}{value};
    my $pending = decode_json($params->{pending}{value});
    my $previous = decode_json($params->{previous}{value});

    $self->{logger}->debug("Calling modify_vrf: $vrf_id");
    return $self->{device}->modify_vrf($previous, $pending);
}

=head2 remove_vrf

  removes a VRF from this switch

=cut

sub remove_vrf{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $vrf = $p_ref->{'vrf_id'}{'value'};

    $self->{'logger'}->debug("Calling remove_vrf: " . $vrf);

    $self->_update_cache();

    my $vrf_obj = $self->_generate_vrf_commands( $vrf );

    my $res = $self->{'device'}->remove_vrf($vrf_obj);
    $self->{'logger'}->debug("after remove vrf");
    $self->{'logger'}->debug("Results: " . Data::Dumper::Dumper($res));
    return $res;
}

=head2 diff

Proxies diff signal to the underlying device object.

=cut
sub diff {
    my $self  = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $force_diff = $p_ref->{'force_diff'}{'value'};

    $self->{'logger'}->debug("Calling Switch.diff");
    $self->_update_cache();

    $self->{'logger'}->debug("Active VRFS: " . Dumper($self->{'vrfs'}));
    my $to_be_removed = $self->{'device'}->get_config_to_remove( circuits => $self->{'ckts'}, vrfs => $self->{'vrfs'} );
    if (!defined $to_be_removed) {
        $self->{'logger'}->error('Could not communicate with device.');
        return FWDCTL_FAILURE;
    }
    $self->{'logger'}->debug("Config to remove: " . Dumper($to_be_removed));

    return $self->{'device'}->diff(circuits => $self->{'ckts'}, vrfs => $self->{'vrfs'}, force_diff =>  $force_diff, remove => $to_be_removed);
}

=head2 get_diff_text

=cut

sub get_diff_text {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{'success_callback'};
    my $error   = $method->{'error_callback'};

    $self->{'logger'}->debug("Calling Switch.get_diff_text");
    $self->_update_cache();
    $self->{'logger'}->debug("Active VRFS: " . Dumper($self->{'vrfs'}));

    my $to_be_removed = $self->{'device'}->get_config_to_remove(
        circuits => $self->{'ckts'},
        vrfs => $self->{'vrfs'}
    );

    my $diff = $self->{'device'}->get_diff_text(
        circuits => $self->{'ckts'},
        vrfs => $self->{'vrfs'},
        remove => $to_be_removed
    );
    if (defined $diff->{error}) {
        return &$error($diff->{error});
    }

    return &$success($diff->{value});
}

=head2 get_interfaces

returns a list of interfaces from the device

=cut

sub get_interfaces{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    return $self->{'device'}->get_interfaces();
}

=head2 get_routed_lsps

takes a routing table name; returns a map where the keys are
circuit_ids and the values are an array of LSPs originating from the
device that are associated with that circuit

=cut

sub get_routed_lsps{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    $self->_update_cache();
    return $self->{'device'}->get_routed_lsps(table => $p_ref->{'table'}{'value'}, circuits => $self->{'ckts'});
}

=head2 get_isis_adjacencies

    returns a list of isis_adjacencies on the device

=cut

sub get_isis_adjacencies{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    return $self->{'device'}->get_isis_adjacencies();
}

=head2 get_LSPs

    returns the details of all of the LSPs on the device

=cut

sub get_LSPs{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    return $self->{'device'}->get_LSPs();
}


=head2 get_vrf_stats

=cut

sub get_vrf_stats{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $success_cb = $m_ref->{success_callback};
    my $error_cb = $m_ref->{error_callback};

    return $self->{'device'}->get_vrf_stats($success_cb, $error_cb);
}

=head2 get_lsp_paths

returns a map from LSP-name to [array of IP addresses for links along the LSP path]
for each LSP on the switch

=cut

sub get_lsp_paths{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $success_cb = $m_ref->{success_callback};
    my $error_cb = $m_ref->{error_callback};

    return $self->{'device'}->get_lsp_paths($success_cb, $error_cb);
}

sub _generate_commands{
    my $self = shift;
    my $ckt_id = shift;

    my $obj = $self->{'ckts'}->{$ckt_id};
    $obj->{'circuit_id'} = $ckt_id;
    return $obj;
}

sub _generate_vrf_commands{
    my $self = shift;
    my $vrf_id = shift;

    my $obj = $self->{'vrfs'}->{$vrf_id};
    $obj->{'vrf_id'} = $vrf_id;
    return $obj;
}


1;
