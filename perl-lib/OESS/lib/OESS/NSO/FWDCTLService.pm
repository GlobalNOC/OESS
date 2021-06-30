package OESS::NSO::FWDCTLService;

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
use OESS::NSO::ConnectionCache;
use OESS::NSO::FWDCTL;
use OESS::RabbitMQ::Dispatcher;
use OESS::VRF;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;
use constant FWDCTL_BLOCKED     => 4;


=head1 OESS::NSO::FWDCTLService

=cut

=head2 new

=cut
sub new {
    my $class = shift;
    my $args  = {
        config     => '/etc/oess/database.xml',
        config_obj => undef,
        logger     => Log::Log4perl->get_logger('OESS.NSO.FWDCTL'),
        @_
    };
    my $self = bless $args, $class;

    if (!defined $self->{config_obj}) {
        $self->{config_obj} = new OESS::Config(config_filename => $self->{config_filename});
    }

    $self->{db} = new OESS::DB(config => $self->{config_obj}->filename);
    $self->{nodes} = {};
    $self->{nso} = new OESS::NSO::Client(config => $self->{config_obj});

    my $cache = new OESS::NSO::ConnectionCache();
    $self->{fwdctl} = new OESS::NSO::FWDCTL(
        connection_cache => $cache,
        config_obj       => $self->{config_obj},
        db               => $self->{db},
        nso              => $self->{nso}
    );

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
    my $nodes = OESS::DB::Node::fetch_all(db => $self->{db}, controller => 'nso');
    if (!defined $nodes) {
        warn "Couldn't lookup nodes. FWDCTL will not provision on any existing nodes.";
        $self->{logger}->error("Couldn't lookup nodes. Discovery will not provision on any existing nodes.");
    }
    foreach my $node (@$nodes) {
        $self->{nodes}->{$node->{node_id}} = $node;
    }

    my $err = $self->{fwdctl}->update_cache;
    if (defined $err) {
        warn $err;
        $self->{logger}->error($err);
    }

    # Setup polling subroutines
    $self->{connection_timer} = AnyEvent->timer(
        after    => 5,
        interval => 30,
        cb       => sub { $self->diff(@_); }
    );

    $self->{dispatcher} = new OESS::RabbitMQ::Dispatcher(
        queue => 'NSO-FWDCTL',
        topic => 'NSO.FWDCTL.RPC'
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
        callback => sub { $self->deleteVrf(@_) },
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

    my $err = $self->{fwdctl}->addVlan(
        circuit_id => $params->{circuit_id}{value}
    );
    if (defined $err) {
        $self->{logger}->error($err);
        return &$error($err);
    }
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

    my $err = $self->{fwdctl}->deleteVlan(
        circuit_id => $params->{circuit_id}{value}
    );
    if (defined $err) {
        $self->{logger}->error($err);
        return &$error($err);
    }
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

    my $err = $self->{fwdctl}->modifyVlan(
        pending => $params->{pending}{value}
    );
    if (defined $err) {
        $self->{logger}->error($err);
        return &$error($err);
    }
    return &$success({ status => FWDCTL_SUCCESS });
}

=head2 addVrf

=cut
sub addVrf {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    my $err = $self->{fwdctl}->addVrf(
        vrf_id => $params->{vrf_id}{value}
    );
    if (defined $err) {
        $self->{logger}->error($err);
        return &$error($err);
    }
    return &$success({ status => FWDCTL_SUCCESS });
}

=head2 deleteVrf

=cut
sub deleteVrf {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    my $err = $self->{fwdctl}->deleteVrf(
        vrf_id => $params->{vrf_id}{value}
    );
    if (defined $err) {
        $self->{logger}->error($err);
        return &$error($err);
    }
    return &$success({ status => FWDCTL_SUCCESS });
}

=head2 modifyVrf

=cut
sub modifyVrf {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    my $err = $self->{fwdctl}->modifyVrf(
        pending => $params->{pending}{value}
    );
    if (defined $err) {
        $self->{logger}->error($err);
        return &$error($err);
    }
    return &$success({ status => FWDCTL_SUCCESS });
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

    my $err = $self->{fwdctl}->diff;
    if (defined $err) {
        $self->{logger}->error($err);
        return;
    }
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

    my $node_id = $params->{node_id}{value};
    my $node_name = "";

    my ($diff, $err) = $self->{fwdctl}->get_diff_text(node_id => $node_id);
    if (defined $err) {
        $self->{logger}->error($err);
        return &$error($err);
    }
    return &$success($diff);
}

=head2 new_switch

=cut
sub new_switch {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{'success_callback'};
    my $error   = $method->{'error_callback'};

    my $err = $self->{fwdctl}->new_switch(node_id => $params->{node_id}{value});
    if (defined $err) {
        $self->{logger}->error($err);
        return &$error($err);
    }
    return &$success({ status => 1 });
}

=head2 update_cache

update_cache reads all connections from the database and loads them
into an in-memory cache.

=cut
sub update_cache {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    my $err = $self->{fwdctl}->update_cache;
    if (defined $err) {
        $self->{logger}->error($err);
        return &$error($err);
    }
    return &$success({ status => 1 });
}

1;
