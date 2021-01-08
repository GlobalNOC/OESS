package OESS::NSO::FWDCTL;

use AnyEvent;
use Data::Dumper;
use GRNOC::RabbitMQ::Method;
use GRNOC::WebService::Regex;
use HTTP::Request::Common;
use JSON;
use Log::Log4perl;
use LWP::UserAgent;
use XML::LibXML;

use OESS::Config;
use OESS::DB;
use OESS::DB::Node;
use OESS::L2Circuit;
use OESS::Node;
use OESS::NSO::Client;
use OESS::RabbitMQ::Dispatcher;
use OESS::VRF;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;
use constant FWDCTL_BLOCKED     => 4;

=head1 OESS::NSO::FWDCTL

=cut

=head2 new

=cut
sub new {
    my $class = shift;
    my $args  = {
        config          => undef,
        config_filename => '/etc/oess/database.xml',
        logger          => Log::Log4perl->get_logger('OESS.NSO.FWDCTL'),
        @_
    };
    my $self = bless $args, $class;

    if (!defined $self->{config}) {
        $self->{config} = new OESS::Config(config_filename => $self->{config_filename});
    }
    $self->{cache} = {};
    $self->{db} = new OESS::DB(config => $self->{config}->filename);
    $self->{nodes} = {};
    $self->{nso} = new OESS::NSO::Client(config => $self->{config});

    # When this process receives sigterm send an event to notify all
    # children to exit cleanly.
    $SIG{TERM} = sub {
        $self->stop;
    };

    return $self;
}

=head2 start

start configures polling timers, loads in-memory cache of l2 and l3
connections, and sets up a rabbitmq dispatcher for RCP calls into FWDCTL.

=cut
sub start {
    my $self = shift;

    # Load devices from database
    my $nodes = OESS::DB::Node::fetch_all(db => $self->{db});
    if (!defined $nodes) {
        warn "Couldn't lookup nodes. FWDCTL will not provision on any existing nodes.";
        $self->{logger}->error("Couldn't lookup nodes. Discovery will not provision on any existing nodes.");
    }
    foreach my $node (@$nodes) {
        $self->{nodes}->{$node->{node_id}} = $node;
    }

    $self->_update_cache;

    # Setup polling subroutines
    $self->{connection_timer} = AnyEvent->timer(
        after    => 5,
        interval => 30,
        cb       => sub { $self->diff(@_); }
    );

    $self->{dispatcher} = new OESS::RabbitMQ::Dispatcher(
        queue => 'MPLS-FWDCTL',
        topic => 'MPLS.FWDCTL.RPC'
    );

    my $add_vlan = GRNOC::RabbitMQ::Method->new(
        name => "addVlan",
        async => 1,
        callback => sub { $self->addVlan(@_) },
        description => "addVlan provisions a l2 connection"
    );
    $add_vlan->add_input_parameter(
        name => "circuit_id",
        description => "Id of the l2 connection to add",
        required => 1,
        attern => $GRNOC::WebService::Regex::INTEGER
    );
    $self->{dispatcher}->register_method($add_vlan);

    my $delete_vlan = GRNOC::RabbitMQ::Method->new(
        name => "deleteVlan",
        async => 1,
        callback => sub { $self->deleteVlan(@_) },
        description => "deleteVlan removes a l2 connection"
    );
    $delete_vlan->add_input_parameter(
        name => "circuit_id",
        description => "Id of the l2 connection to delete",
        required => 1,
        pattern => $GRNOC::WebService::Regex::INTEGER
    );
    $self->{dispatcher}->register_method($delete_vlan);

    my $modify_vlan = GRNOC::RabbitMQ::Method->new(
        name => "modifyVlan",
        async => 1,
        callback => sub { $self->modifyVlan(@_) },
        description => "modifyVlan modifies an existing l2 connection"
    );
    $modify_vlan->add_input_parameter(
        name => "circuit_id",
        description => "Id of l2 connection to be modified.",
        required => 1,
        pattern => $GRNOC::WebService::Regex::INTEGER
    );
    $modify_vlan->add_input_parameter(
        name => "previous",
        description => "Previous version of the modified l2 connection.",
        required => 1,
        pattern => $GRNOC::WebService::Regex::TEXT
    );
    $modify_vlan->add_input_parameter(
        name => "pending",
        description => "Pending version of the modified l2 connection.",
        required => 1,
        pattern => $GRNOC::WebService::Regex::TEXT
    );
    $self->{dispatcher}->register_method($modify_vlan);

    my $add_vrf = GRNOC::RabbitMQ::Method->new(
        name => "addVrf",
        async => 1,
        callback => sub { $self->addVrf(@_) },
        description => "addVrf provisions a l3 connection"
    );
    $self->{dispatcher}->register_method($add_vrf);

    my $delete_vrf = GRNOC::RabbitMQ::Method->new(
        name => "delVrf",
        async => 1,
        callback => sub { $self->delVrf(@_) },
        description => "delVrf removes a l3 connection"
    );
    $self->{dispatcher}->register_method($delete_vrf);

    my $modify_vrf = GRNOC::RabbitMQ::Method->new(
        name => "modifyVrf",
        async => 1,
        callback => sub { $self->modifyVrf(@_) },
        description => "modifyVrf modifies an existing l3 connection"
    );
    $self->{dispatcher}->register_method($modify_vrf);

    # NOTE It's not expected that any children processes will exist in this
    # version of FWDCTL. Result is hardcoded.
    my $check_child_status = GRNOC::RabbitMQ::Method->new(
        name        => "check_child_status",
        description => "check_child_status returns an event id which will return the final status of all children",
        callback    => sub {
            my $method = shift;
            return { status => 1, event_id => 1 };
        }
    );
    $self->{dispatcher}->register_method($check_child_status);

    # NOTE It's not expected that any children processes will exist in this
    # version of FWDCTL. Result is hardcoded.
    my $get_event_status = GRNOC::RabbitMQ::Method->new(
        name        => "get_event_status",
        description => "get_event_status returns the current status of the event",
        callback    => sub {
            my $method = shift;
            return { status => 1 };
        }
    );
    $get_event_status->add_input_parameter(
        name => "event_id",
        description => "the event id to fetch the current state of",
        required => 1,
        pattern => $GRNOC::WebService::Regex::NAME_ID
    );
    $self->{dispatcher}->register_method($get_event_status);

    # TODO It's not clear if both is_online and echo are required; Please
    # investigate.
    my $echo = GRNOC::RabbitMQ::Method->new(
        name        => "echo",
        description => "echo always returns 1",
        callback    => sub {
            my $method = shift;
            return { status => 1 };
        }
    );
    $self->{dispatcher}->register_method($echo);

    my $get_diff_text = GRNOC::RabbitMQ::Method->new(
        name => 'get_diff_text',
        async => 1,
        callback => sub { $self->get_diff_text(@_); },
        description => "Returns a human readable diff for node_id"
    );
    $get_diff_text->add_input_parameter(
        name => "node_id",
        description => "The node ID to lookup",
        required => 1,
        pattern => $GRNOC::WebService::Regex::INTEGER
    );
    $self->{dispatcher}->register_method($get_diff_text);

    # TODO It's not clear if both is_online and echo are required; Please
    # investigate.
    my $is_online = new GRNOC::RabbitMQ::Method(
        name        => "is_online",
        description => 'is_online returns 1 if this service is available',
        async       => 1,
        callback    => sub {
            my $method = shift;
            return $method->{success_callback}({ successful => 1 });
        }
    );
    $self->{dispatcher}->register_method($is_online);

    my $new_switch = new GRNOC::RabbitMQ::Method(
        name        => 'new_switch',
        description => 'new_switch adds a new switch to FWDCTL',
        async       => 1,
        callback    => sub { $self->new_switch(@_); }
    );
    $new_switch->add_input_parameter(
        name        => 'node_id',
        description => 'Id of the new node',
        required    => 1,
        pattern     => $GRNOC::WebService::Regex::NUMBER_ID
    );
    $self->{dispatcher}->register_method($new_switch);

    my $update_cache = GRNOC::RabbitMQ::Method->new(
        name => 'update_cache',
        async => 1,
        callback => sub { $self->update_cache(@_) },
        description => "Rewrites the connection cache file"
    );
    $self->{dispatcher}->register_method($update_cache);

    $self->{dispatcher}->start_consuming;
    return 1;
}

=head2 stop

=cut
sub stop {
    my $self = shift;
    $self->{logger}->info('Stopping OESS::NSO::FWDCTL.');
    $self->{dispatcher}->stop_consuming;
}

=head2 addVlan

=cut
sub addVlan {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    my $conn = new OESS::L2Circuit(
        db => $self->{db},
        circuit_id => $params->{circuit_id}{value}
    );
    $conn->load_endpoints;

    my $err = $self->{nso}->create_l2connection($conn);
    if (defined $err) {
        $self->{logger}->error($err);
        return &$error($err);
    }

    $self->_add_connection_to_cache($conn);
    return &$success({ status => FWDCTL_SUCCESS });
}

=head2 deleteVlan

=cut
sub deleteVlan {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    my $conn = new OESS::L2Circuit(
        db => $self->{db},
        circuit_id => $params->{circuit_id}{value}
    );
    $conn->load_endpoints;

    my $err = $self->{nso}->delete_l2connection($params->{circuit_id}{value});
    if (defined $err) {
        $self->{logger}->error($err);
        return &$error($err);
    }

    $self->_del_connection_from_cache($conn);
    return &$success({ status => FWDCTL_SUCCESS });
}

=head2 modifyVlan

=cut
sub modifyVlan {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    my $pending_hash = decode_json($params->{pending}{value});
    my $pending_conn = new OESS::L2Circuit(db => $self->{db}, model => $pending_hash);

    my $err = $self->{nso}->edit_l2connection($pending_conn);
    if (defined $err) {
        $self->{logger}->error($err);
        return &$error($err);
    }

    $self->_add_connection_to_cache($conn);
    return &$success({ status => 1 });
}

=head2 addVrf

=cut
sub addVrf {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    return &$success({ status => 1 });
}

=head2 deleteVrf

=cut
sub deleteVrf {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    return &$success({ status => 1 });
}

=head2 modifyVrf

=cut
sub modifyVrf {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    return &$success({ status => 1 });
}

=head2 diff

diff reads all connections from cache, loads all connections from nso,
determines if a configuration change within nso is required, and if so, make
the change.

In the case of a large change (effects > N connections), the diff is put
into a pending state. Diff states are tracked on a per-node basis.

=cut
sub diff {
    my $self = shift;

    my ($connections, $err) = $self->{nso}->get_l2connections();
    if (defined $err) {
        $self->{logger}->error($err);
        return;
    }

    # After a connection has been sync'd to NSO we remove it from our hash of
    # nso connections. Any connections left in this hash after syncing are not
    # known by OESS and should be removed.
    my $nso_l2connections = {};
    foreach my $conn (@{$connections}) {
        $nso_l2connections->{$conn->{connection_id}} = $conn;
    }

    # Connections are stored in-memory multiple times under each node they're
    # associed with. Keep a record of connections as they're sync'd to prevent a
    # connection from being sync'd more than once.
    my $syncd_connections = {};

    foreach my $node_id (keys %{$self->{cache}}) {
        foreach my $conn_id (keys %{$self->{cache}->{$node_id}}) {

            # Skip connections if they're already sync'd.
            next if defined $syncd_connections->{$conn_id};
            $syncd_connections->{$conn_id} = 1;

            # Compare cached connection against NSO connection. If no difference
            # continue with next connection, otherwise update NSO to align with
            # cache.
            my $conn = $self->{cache}->{$node_id}->{$conn_id};
            if (!$self->_nso_connection_equal_to_cached($conn, $nso_l2connections->{$conn_id})) {
                my $err = $self->{nso}->edit_l2connection($conn);
                if (defined $err) {
                    $self->{logger}->error($err);
                    warn $err;
                }
            }

            delete $nso_l2connections->{$conn_id};
        }
    }

    foreach my $conn_id (keys %{$nso_l2connections}) {
        my $err = $self->{nso}->delete_l2connection($conn_id);
        if (defined $err) {
            $self->{logger}->error($err);
        }
    }

    # TODO Queue up all required changes into an array. If size greater than
    # auto-diff cutoff set diff to pending. Changes should be tracked on a per
    # device basis.
    # Ex. [ {type => 'add-l2', value => OESS::L2Circuit } ]

    warn 'Syncd Connections: ' . Dumper($syncd_connections);

    return 1;
}

=head2 get_diff_text

=cut
sub get_diff_text {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    return &$success({ status => 1 });
}

=head2 new_switch

=cut
sub new_switch {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{'success_callback'};
    my $error   = $method->{'error_callback'};

    if (defined $self->{nodes}->{$params->{node_id}{value}}) {
        $self->{logger}->warn("Node $params->{node_id}{value} already registered with FWDCTL.");
        return &$success({ status => 1 });
    }

    my $node = OESS::DB::Node::fetch(db => $self->{db}, node_id => $params->{node_id}{value});
    if (!defined $node) {
        my $err = "Couldn't lookup node $params->{node_id}{value}. FWDCTL will not properly provision on this node.";
        $self->{logger}->error($err);
        &$error($err);
    }
    $self->{nodes}->{$params->{node_id}{value}} = $node;

    warn "Switch $node->{name} registered with FWDCTL.";
    $self->{logger}->info("Switch $node->{name} registered with FWDCTL.");

    # Make first invocation of polling subroutines
    $self->diff;

    return &$success({ status => 1 });
}

=head2 update_cache

update_cache is a rabbitmq proxy method to _update_cache.

=cut
sub update_cache {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    my $err = $self->_update_cache;
    if (defined $err) {
        $self->{logger}->error($err);
        return &$error($err);
    }
    return &$success({ status => 1 });
}

=head2 _update_cache

_update_cache reads all connections from the database and loads them into an
in-memory cache.

In memory connection cache:
{
    "node-id-1": {
        "conn-id-1": { "eps" : [ "node-id-1", "node-id-2" ] }
    },
    "node-id-2": {
        "conn-id-1": { "eps" : [ "node-id-1", "node-id-2" ] }
    }
}

This implies that a connection is stored under each node. This allows us to
query all connections associated with a single node. Additionally this helps us
track large changes that may effect multiple connections on a single node.

=cut
sub _update_cache {
    my $self = shift;

    my $l2connections = OESS::DB::Circuit::fetch_circuits(
        db => $self->{db}
    );
    if (!defined $l2connections) {
        return "Couldn't load l2connections in update_cache.";
    }

    foreach my $conn (@$l2connections) {
        my $conn_obj = new OESS::L2Circuit(db => $self->{db}, model => $conn);
        $conn_obj->load_endpoints;
        $self->_add_connection_to_cache($conn_obj);
    }

    return;
}

=head2 _del_connection_from_cache

_del_connection_in_cache is a simple helper to correctly remove a connection
object from memory.

=cut
sub _del_connection_from_cache {
    my $self = shift;
    my $conn = shift;

    foreach my $ep (@{$conn->endpoints}) {
        if (!defined $self->{cache}->{$ep->node_id}) {
            next;
        }
        delete $self->{cache}->{$ep->node_id}->{$conn->circuit_id};
    }

    return 1;
}

=head2 _add_connection_to_cache

_add_connection_to_cache is a simple helper to correctly place a connection
object into memory.

=cut
sub _add_connection_to_cache {
    my $self = shift;
    my $conn = shift;

    foreach my $ep (@{$conn->endpoints}) {
        if (!defined $self->{cache}->{$ep->node_id}) {
            $self->{cache}->{$ep->node_id} = {};
        }
        $self->{cache}->{$ep->node_id}->{$conn->circuit_id} = $conn;
    }

    return 1;
}

=head2 _nso_connection_equal_to_cached

_nso_connection_equal_to_cached compares the NSO provided data structure against
the cached connection object. If there is no difference return 1, otherwise
return 0.

NSO L2Connection:

    {
        'connection_id' => 3000,
        'directly-modified' => {
            'services' => [
                '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'0\'][sdp:name=\'3000\']',
                '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'1\'][sdp:name=\'3000\']'
            ],
            'devices' => [
                'xr0'
            ]
        },
        'endpoint' => [
            {
                'bandwidth' => 0,
                'endpoint_id' => 1,
                'interface' => 'GigabitEthernet0/0',
                'tag' => 1,
                'device' => 'xr0'
            },
            {
                'bandwidth' => 0,
                'endpoint_id' => 2,
                'interface' => 'GigabitEthernet0/1',
                'tag' => 1,
                'device' => 'xr0'
            }
        ],
        'device-list' => [
            'xr0'
        ],
        'modified' => {
            'services' => [
                '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'1\'][sdp:name=\'3000\']',
                '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'0\'][sdp:name=\'3000\']'
            ],
            'devices' => [
                'xr0'
            ]
        }
    }

=cut
sub _nso_connection_equal_to_cached {
    my $self = shift;
    my $conn = shift;
    my $nsoc = shift; # NSOConnection

    my $conn_ep_count = @{$conn->endpoints};
    my $nsoc_ep_count = @{$nsoc->{endpoint}};
    if (@{$conn->endpoints} != @{$nsoc->{endpoint}}) {
        warn "ep count wrong";
        return 0;
    }

    my $ep_index = {};
    foreach my $ep (@{$conn->endpoints}) {
        if (!defined $ep_index->{$ep->node}) {
            $ep_index->{$ep->node} = {};
        }
        $ep_index->{$ep->node}->{$ep->interface} = $ep;
    }

    foreach my $ep (@{$nsoc->{endpoint}}) {
        if (!defined $ep_index->{$ep->{device}}->{$ep->{interface}}) {
            warn "ep not in cache";
            return 0;
        }
        my $ref_ep = $ep_index->{$ep->{device}}->{$ep->{interface}};

        warn "band" if $ep->{bandwidth} != $ref_ep->bandwidth;
        warn "tag" if $ep->{tag} != $ref_ep->tag;
        warn "inner_tag" if $ep->{inner_tag} != $ref_ep->inner_tag;

        # Compare endpoints
        return 0 if $ep->{bandwidth} != $ref_ep->bandwidth;
        return 0 if $ep->{tag} != $ref_ep->tag;
        return 0 if $ep->{inner_tag} != $ref_ep->inner_tag;

        delete $ep_index->{$ep->{device}}->{$ep->{interface}};
    }

    foreach my $key (keys %{$ep_index}) {
        my @leftovers = keys %{$ep_index->{$key}};
        warn "leftover eps: ".Dumper(@leftovers) if @leftovers > 0;
        return 0 if @leftovers > 0;
    }

    return 1;
}

1;
