use strict;
use warnings;

package OESS::NSO::Discovery;

use AnyEvent;
use Data::Dumper;
use GRNOC::RabbitMQ::Method;
use HTTP::Request::Common;
use JSON;
use Log::Log4perl;
use LWP::UserAgent;
use XML::LibXML;

use OESS::Config;
use OESS::DB;
use OESS::DB::Interface;
use OESS::DB::Node;
use OESS::Node;
use OESS::RabbitMQ::Dispatcher;

use constant MAX_TSDS_MESSAGES => 30;
use constant TSDS_RIB_TYPE => 'rib_table';
use constant TSDS_PEER_TYPE => 'bgp_peer';
use constant VRF_STATS_INTERVAL => 240;

=head1 OESS::NSO::Discovery

=cut

=head2 new

=cut
sub new {
    my $class = shift;
    my $args  = {
        config          => '/etc/oess/database.xml',
        config_obj      => undef,
        nso             => undef, # OESS::NSO:Client or OESS::NSO::ClientStub
        logger          => Log::Log4perl->get_logger('OESS.NSO.Discovery'),
        @_
    };
    my $self = bless $args, $class;

    if (!defined $self->{config_obj}) {
        $self->{config_obj} = new OESS::Config(config_filename => $self->{config});
    }
    $self->{db} = new OESS::DB(config => $self->{config_obj}->filename);
    $self->{nodes} = {};

    $self->{www} = new LWP::UserAgent;
    my $host = $self->{config_obj}->nso_host;
    $host =~ s/http(s){0,1}:\/\///g; # Strip http:// or https:// from string
    $self->{www}->credentials($host, "restconf", $self->{config_obj}->nso_username, $self->{config_obj}->nso_password);

    # When this process receives sigterm send an event to notify all
    # children to exit cleanly.
    $SIG{TERM} = sub {
        $self->stop;
    };

    return $self;
}

=head2 fetch_platform

=cut
sub fetch_platform {
    my $self = shift;

    $self->{logger}->info("Calling fetch_platform.");

    my $results = {};

    my $cv = AnyEvent->condvar;
    $cv->begin(
        sub {
            my $cv = shift;
            foreach my $key (keys %{$self->{nodes}}) {
                my $node   = $self->{nodes}->{$key};
                my $result = $results->{$node->{name}};
                next if !defined $result;

                $self->{db}->start_transaction;
                my $device = new OESS::Node(db => $self->{db}, name => $node->{name});
                if (!defined $device) {
                    warn "Couldn't find node $result->{name}.";
                    $self->{logger}->error("Couldn't find node $result->{name}.");
                }

                $device->model($result->{model});
                $device->sw_version($result->{version});
                $device->vendor('Cisco') if ($result->{name} eq 'ios-xr');
                $device->update;
                $self->{db}->commit;
            }
            $cv->send;
        }
    );
    foreach my $key (keys %{$self->{nodes}}) {
        my $node = $self->{nodes}->{$key};

        $cv->begin;
        $self->{nso}->get_platform(
            $node->{short_name},
            sub {
                my ($result, $err) = @_;
                if (defined $err) {
                    $self->{logger}->error("fetch_platform: $err");
                    $results->{$node->{name}} = undef;
                } else {
                    $results->{$node->{name}} = $result;
                }
                $cv->end;
            }
        );
    }
    $cv->end;

    $self->{logger}->info("Platform data fetched from NSO.");
}

=head2 fetch_interfaces

fetch_interfaces queries each device for interface configuration and
operational state.

=cut
sub fetch_interfaces {
    my $self = shift;
    $self->{logger}->info("Calling fetch_interfaces.");

    my $results = {};

    my $cv = AnyEvent->condvar;
    $cv->begin(
        sub {
            my $cv = shift;

            my $types = ["Bundle-Ether", "GigabitEthernet", "TenGigE", "FortyGigE", "HundredGigE", "FourHundredGigE"];
            my $ports = [];
            # TODO Get negotiated interface capacity/speed via NSO; Required for correct Bundle-Ether capacity/speed
            # if not set via device configuration.
            my $default_speeds = {
                "Bundle-Ether"    =>  10000,
                "GigabitEthernet" =>   1000,
                "TenGigE"         =>  10000,
                "FortyGigE"       =>  40000,
                "HundredGigE"     => 100000,
                "FourHundredGigE" => 400000,
            };

            foreach my $key (keys %{$self->{nodes}}) {
                my $node   = $self->{nodes}->{$key};
                my $result = $results->{$node->{name}};
                next if !defined $result;

                foreach my $type (@$types) {
                    next if !defined $result->{$type};

                    my $default_speed = $default_speeds->{$type};
                    foreach my $port (@{$result->{$type}}) {
                        my $port_info = {
                            admin_state => (exists $port->{shutdown}) ? 'down' : 'up',
                            bandwidth   => (exists $port->{speed}) ? $port->{speed} : $default_speed,
                            description => (exists $port->{description}) ? $port->{description} : '',
                            mtu         => (exists $port->{mtu}) ? $port->{mtu} : 0,
                            name        => $type . $port->{id},
                            node        => $node->{name},
                            node_id     => $node->{node_id}
                        };
                        push @$ports, $port_info;
                    }
                }
            }

            $self->{db}->start_transaction;
            foreach my $data (@$ports) {
                my $port = new OESS::Interface(db => $self->{db}, node => $data->{node}, name => $data->{name});
                if (defined $port) {
                    $port->admin_state($data->{admin_state});
                    $port->operational_state($data->{admin_state}); # Using admin_state as best guess for now
                    $port->bandwidth($data->{bandwidth});
                    $port->description($data->{description});
                    $port->mtu($data->{mtu});
                    $port->update_db;
                } else {
                    warn "Couldn't find interface $data->{node} $data->{name}; Creating interface.";
                    $self->{logger}->warn("Couldn't find interface $data->{node} $data->{name}; Creating interface.");

                    $port = new OESS::Interface(db => $self->{db}, model => {
                        admin_state => $data->{admin_state},
                        bandwidth => $data->{bandwidth},
                        description => $data->{description},
                        mtu => $data->{mtu},
                        name => $data->{name},
                        operational_state => $data->{admin_state} # Using admin_state as best guess for now
                    });

                    my ($port_id, $port_err) = $port->create(node_id => $data->{node_id});
                    if (defined $port_err) {
                        warn "Couldn't create interface $data->{node} $data->{name}.";
                        $self->{logger}->error("Couldn't create interface $data->{node} $data->{name}.")
                    }
                }
            }
            $self->{db}->commit;
            $self->{logger}->info("Interfaces fetched from NSO.");

            $cv->send;
        }
    );
    foreach my $key (keys %{$self->{nodes}}) {
        my $node = $self->{nodes}->{$key};

        $cv->begin;
        $self->{nso}->get_interfaces(
            $node->{short_name},
            sub {
                my ($result, $err) = @_;
                if (defined $err) {
                    $self->{logger}->error("fetch_interfaces: $err");
                    $results->{$node->{name}} = undef;
                } else {
                    $results->{$node->{name}} = $result;
                }
                $cv->end;
            }
        );
    }
    $cv->end;
}

=head2 link_handler

=cut
sub link_handler {
    my $self = shift;


    # get links from nso
    $self->{nso}->get_backbones(sub {
        my ($backbones, $err) = @_;
        if (defined $err) {
            $self->{logger}->error($err);
            return;
        }

        # lookup links name and put into index
        my ($links, $links_err) = OESS::DB::Link::fetch_all(db => $self->{db}, controller => 'nso');

        my $links_index = {};
        foreach my $link (@$links) {
            $links_index->{$link->{name}} = $link;
        }

        # lookup nso links in index
        foreach my $bb (@$backbones) {
            my $n = (defined $bb->{summary}->{endpoint}) ? scalar @{$bb->{summary}->{endpoint}} : 0;
            if ($n != 2) {
                $self->{logger}->error("Couldn't process link $bb->{name}. Got $n endpoints but only expected 2.");
                next;
            }

            # Lookup interface ids of backbone edges
            my $eps = [];
            foreach my $ep (@{$bb->{summary}->{endpoint}}) {
                my $id = OESS::DB::Interface::get_interface(
                    db        => $self->{db},
                    interface => $ep->{'if-full'},
                    short_name => $ep->{'device'},
                );
                if (!defined $id) {
                    $self->{logger}->warn("Couldn't find interface for $ep->{'device'} - $ep->{'if-full'} in database.");
                    next;
                }
                push @$eps, { id => $id, ip => $ep->{'ipv4-address'} };
            }
            if (@$eps != 2) {
                $self->{logger}->error("Couldn't sync link $bb->{name} due to interface lookup errors.");
                next;
            }

            # We assume admin-state represents both status and
            # link-state. This is likely a bad assumption.
            if ($bb->{'admin-state'} eq 'in-service') {
                $bb->{link_state} = 'active';
                $bb->{status} = 'up';
            } else {
                $bb->{link_state} = 'available';
                $bb->{status} = 'down';
            }

            #  if !exists create
            if (!defined $links_index->{$bb->{name}}) {
                $self->{logger}->info("Creating link $bb->{name}.");

                my ($link_id, $link_err) = OESS::DB::Link::create(
                    db    => $self->{db},
                    model => {
                        name           => $bb->{name},
                        status         => $bb->{status},
                        metric         => 1,
                        interface_a_id => $eps->[0]->{id},
                        ip_a           => $eps->[0]->{ip},
                        interface_z_id => $eps->[1]->{id},
                        ip_z           => $eps->[1]->{ip},
                    }
                );
                $self->{logger}->error($link_err) if defined $link_err;
            }
            #  el update if interfaces changed
            else {
                my $link = $links_index->{$bb->{name}};

                my $interfaces_changed = 1;
                if ($eps->[0]->{id} == $link->{interface_a_id} && $eps->[1]->{id} == $link->{interface_z_id}) {
                    $interfaces_changed = 0;
                }
                if ($eps->[0]->{id} == $link->{interface_z_id} && $eps->[1]->{id} == $link->{interface_a_id}) {
                    $interfaces_changed = 0;
                }
                my $state_changed = ($bb->{link_state} ne $link->{link_state}) ? 1 : 0;
                my $status_changed = ($bb->{status} ne $link->{status}) ? 1 : 0;

                if ($interfaces_changed || $state_changed || $status_changed) {
                    my $msg = "Updating link $bb->{name}:";
                    $msg .= " interface changed." if $interfaces_changed;
                    $msg .= " state changed." if $state_changed;
                    $msg .= " status changed." if $status_changed;
                    $self->{logger}->info($msg);

                    my ($link_id, $link_err) = OESS::DB::Link::update(
                        db   => $self->{db},
                        link => {
                            link_id => $link->{link_id},
                            link_state => $bb->{link_state},
                            status => $bb->{status},
                            interface_a_id => $eps->[0]->{id},
                            ip_a           => $eps->[0]->{ip},
                            interface_z_id => $eps->[1]->{id},
                            ip_z           => $eps->[1]->{ip},
                        }
                    );
                    $self->{logger}->error($link_err) if defined $link_err;
                }

                #  remove link from index
                delete $links_index->{$bb->{name}};
            }

        }

        # decom all links still in index
        foreach my $name (keys %$links_index) {
            my $link = $links_index->{$name};
            $self->{logger}->info("Decommissioning link $link->{name}.");

            my ($link_id, $link_err) = OESS::DB::Link::update(
                db   => $self->{db},
                link => {
                    link_id        => $link->{link_id},
                    link_state     => 'decom',
                    status         => 'down',
                    interface_a_id => $link->{interface_a_id},
                    ip_a           => $link->{ip_a},
                    interface_z_id => $link->{interface_z_id},
                    ip_z           => $link->{ip_z},
                }
            );
            $self->{logger}->error($link_err) if defined $link_err;
        }

        return 1;
    });

    return 1;
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
        $self->{logger}->warn("Node $params->{node_id}{value} already registered with Discovery.");
        return &$success({ status => 1 });
    }

    my $node = OESS::DB::Node::fetch(db => $self->{db}, node_id => $params->{node_id}{value});
    if (!defined $node) {
        my $err = "Couldn't lookup node $params->{node_id}{value}. Discovery will not properly complete on this node.";
        $self->{logger}->error($err);
        return &$error($err);
    }
    $self->{nodes}->{$params->{node_id}{value}} = $node;

    warn "Switch $node->{name} registered with NSO.Discovery.";
    $self->{logger}->info("Switch $node->{name} registered with NSO.Discovery.");

    # Make first invocation of polling subroutines
    $self->fetch_platform;
    $self->fetch_interfaces;

    return &$success({ status => 1 });
}

=head2 start

=cut
sub start {
    my $self = shift;

    # Load devices from database
    my $nodes = OESS::DB::Node::fetch_all(db => $self->{db}, controller => 'nso');
    if (!defined $nodes) {
        warn "Couldn't lookup nodes. Discovery will not collect data on any existing nodes.";
        $self->{logger}->error("Couldn't lookup nodes. Discovery will not collect data on any existing nodes.");
    }
    foreach my $node (@$nodes) {
        $self->{nodes}->{$node->{node_id}} = $node;
    }

    # Setup polling subroutines
    $self->{device_timer} = AnyEvent->timer(
        after    => 10,
        interval => 60,
        cb       => sub { $self->fetch_platform(@_); }
    );
    $self->{interface_timer} = AnyEvent->timer(
        after    =>  60,
        interval => 120,
        cb       => sub { $self->fetch_interfaces(@_); }
    );
    $self->{link_timer} = AnyEvent->timer(
        after    =>  90,
        interval => 120,
        cb       => sub { $self->link_handler(@_); }
    );
    $self->{vrf_stats_time} = AnyEvent->timer(
        after    =>  30,
        interval => VRF_STATS_INTERVAL,
        cb       => sub { $self->vrf_stats_handler(@_); }
    );


    $self->{dispatcher} = new OESS::RabbitMQ::Dispatcher(
        queue => 'NSO-Discovery',
        topic => 'NSO.Discovery.RPC'
    );

    my $new_switch = new GRNOC::RabbitMQ::Method(
        name        => 'new_switch',
        description => 'Add a new switch process to Discovery',
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

    my $is_online = new GRNOC::RabbitMQ::Method(
        name        => "is_online",
        description => 'Return if this service is online',
        async       => 1,
        callback    => sub {
            my $method = shift;
            return $method->{success_callback}({ successful => 1 });
        }
    );
    $self->{dispatcher}->register_method($is_online);

    return 1;
}


=head2 vrf_stats_handler

=cut
sub vrf_stats_handler {
    my $self = shift;
    $self->{logger}->info("Calling vrf_stats_handler.");

    my $results = {};

    my $cv = AnyEvent->condvar;
    $cv->begin(
        sub {
            my $cv = shift;
            foreach my $key (keys %{$self->{nodes}}) {
                my $node = $self->{nodes}->{$key};
                next if !defined $results->{$node->{name}};

                $self->handle_vrf_stats(node => $node->{name}, stats => $results->{$node->{name}});
            }
            $self->{logger}->info("Statistics submitted to TSDS.");
            $cv->send;
        }
    );
    foreach my $key (keys %{$self->{nodes}}) {
        my $node = $self->{nodes}->{$key};
        
        $cv->begin;
        $self->{nso}->get_vrf_statistics(
            $node->{short_name},
            sub {
                my ($result, $err) = @_;
                if (defined $err) {
                    $self->{logger}->error("vrf_stats_handler: $err");
                    $results->{$node->{name}} = [];
                } else {
                    $results->{$node->{name}} = $result;
                }
                $cv->end;
            }
        );
    }
    $cv->end;
}

=head2 handle_vrf_stats

=cut
sub handle_vrf_stats {
    my $self = shift;
    my %params = @_;

    my $node  = $params{'node'};
    my $stats = $params{'stats'};

    return if (!defined $stats || @$stats == 0);

    my $time     = time();
    my $all_val  = [];

    while (@$stats > 0) {
        my $stat = shift @$stats;
        
        my $prev_stat = $self->{previous_peer}->{$stat->{node}}->{$stat->{vrf_name}}->{$stat->{remote_ip}};
        if (!defined $prev_stat) {
            $self->{logger}->warn("Previous stats unavailable for $stat->{node}. Collection will resume with the next datapoints.");
            $self->{previous_peer}->{$stat->{node}}->{$stat->{vrf_name}}->{$stat->{remote_ip}} = $stat;
            next;
        }

        # Most neighbor stats we collected from Juniper have no direct
        # mapping to Cisco.
        my $rib_data = {
            total_prefix_count               => 0,
            received_prefix_count            => 0,
            accepted_prefix_count            => $stat->{prefixes_accepted},
            active_prefix_count              => $stat->{prefixes_accepted},
            suppressed_prefix_count          => $stat->{prefixes_suppressed},
            history_prefix_count             => 0,
            damped_prefix_count              => 0,
            pending_prefix_count             => 0,
            total_external_prefix_count      => 0,
            active_external_prefix_count     => 0,
            accepted_external_prefix_count   => 0,
            suppressed_external_prefix_count => 0,
            total_internal_prefix_count      => 0,
            active_internal_prefix_count     => 0,
            accepted_internal_prefix_count   => 0,
            suppressed_internal_prefix_count => 0,
        };
        my $rib_metadata = {
            routing_table => $stat->{vrf_name},
            node          => $node,
        };
        push @$all_val, {
            type     => TSDS_RIB_TYPE,
            time     => $time,
            interval => VRF_STATS_INTERVAL,
            values   => $rib_data,
            meta     => $rib_metadata,
        };

        my $peer_data = {
            output_messages   => ($stat->{messages_sent} - $prev_stat->{messages_sent}) / VRF_STATS_INTERVAL,
            input_messages    => ($stat->{messages_received} - $prev_stat->{messages_received}) / VRF_STATS_INTERVAL,
            route_queue_count => 0,
            flap_count        => 0,
            state             => ($stat->{connection_state} eq 'BGP_ST_ESTAB') ? 1 : 0,
        };
        my $peer_metadata = {
            peer_address => $stat->{remote_ip},
            vrf          => $stat->{vrf_name},
            as           => $stat->{remote_as},
            node         => $node,
        };
        push @$all_val, {
            type     => TSDS_PEER_TYPE,
            time     => $time,
            interval => VRF_STATS_INTERVAL,
            values   => $peer_data,
            meta     => $peer_metadata,
        };

        # Update previous stat to current stat; On the next iteration
        # this stat will be the previous.
        $self->{previous_peer}->{$stat->{node}}->{$stat->{vrf_name}}->{$stat->{remote_ip}} = $stat;

        eval {
            $self->{logger}->debug("Updating VRF $stat->{vrf_name} neighbor $stat->{remote_ip} on $stat->{node} with state $peer_data->{state}.");
            my $q = "
                update vrf_ep_peer set operational_state=? where peer_ip like ? and vrf_ep_id in (
                  select vrf_ep_id from vrf_ep where vrf_id=?
                )
            ";
            $self->{db}->execute_query(
                $q,
                [ $peer_data->{state}, "$stat->{remote_ip}/%", $stat->{vrf_id} ]
            );
        };
        if ($@) {
            $self->{logger}->warn("Couldn't update VRF $stat->{vrf_name} neighbor $stat->{remote_ip} on $stat->{node} with state $peer_data->{state}: $@");
        }

        if (@$all_val >= MAX_TSDS_MESSAGES || @$stats == 0) {
            eval {
                my $tsds_res = $self->{tsds}->add_data(data => encode_json($all_val));
                if (!defined $tsds_res) {
                    die $self->{tsds}->get_error;
                }
                if (defined $tsds_res->{error}) {
                    die $tsds_res->{error_text};
                }
            };
            if ($@) {
                $self->{logger}->error("Error submitting statistics to TSDS: $@");
            }
            $all_val = [];
        }
    }
}


=head2 stop

=cut
sub stop {
    my $self = shift;
    $self->{logger}->info('Stopping OESS::NSO::Discovery.');
    $self->{dispatcher}->stop_consuming;
}

1;
