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
use constant VRF_STATS_INTERVAL => 60;

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

=head2 connection_handler

=cut
sub connection_handler {
    my $self = shift;

    return 1;
}

=head2 device_handler

device_handler queries each devices for basic system info:
- loopback address
- firmware version

=cut
sub device_handler {
    my $self = shift;
    $self->{logger}->info("Calling device_handler.");

    foreach my $key (keys %{$self->{nodes}}) {
        my $node = $self->{nodes}->{$key};

        my $dom = eval {
            my $res = $self->{www}->get($self->{config_obj}->nso_host . "/restconf/data/tailf-ncs:devices/device=$node->{name}/platform");
            return XML::LibXML->load_xml(string => $res->content);
        };
        if ($@) {
            warn "tailf-ncs:devices/device=$node->{name}/platform: $@";
            $self->{logger}->error("tailf-ncs:devices/device=$node->{name}/platform: $@");
            next;
        }

        my $data = eval {
            return {
                name          => $node->{name},
                platform      => $dom->findvalue('/ncs:platform/ncs:name'),
                version       => $dom->findvalue('/ncs:platform/ncs:version'),
                model         => $dom->findvalue('/ncs:platform/ncs:model'),
                serial_number => $dom->findvalue('/ncs:platform/ncs:serial-number')
            };
        };
        if ($@) {
            warn 'device:' . $@;
            $self->{logger}->error('device:' . $@);
            next;
        }

        $self->{db}->start_transaction;
        my $device = new OESS::Node(db => $self->{db}, name => $data->{name});
        if (!defined $device) {
            warn "Couldn't find node $data->{name}.";
            $self->{logger}->error("Couldn't find node $data->{name}.");
        }
        $device->name($data->{name});
        $device->model($data->{model});
        $device->sw_version($data->{version});
        $device->vendor('Cisco') if ($data->{platform} eq 'ios-xr');
        $device->update;
        $self->{db}->commit;
    }
    return 1;
}

=head2 interface_handler

interface_handler queries each device for interface configuration and
operational state.

=cut
sub interface_handler {
    my $self = shift;
    $self->{logger}->info("Calling interface_handler.");

    foreach my $key (keys %{$self->{nodes}}) {
        my $node = $self->{nodes}->{$key};

        my $dom = eval {
            my $res = $self->{www}->get($self->{config_obj}->nso_host . "/restconf/data/tailf-ncs:devices/device=$node->{name}/config/tailf-ned-cisco-ios-xr:interface");
            return XML::LibXML->load_xml(string => $res->content);
        };
        if ($@) {
            # Don't log Empty String error as there are simply no interfaces
            if ($@ !~ /Empty String/g) {
                warn 'tailf-ned-cisco-ios-xr:interface:' . $@;
                $self->{logger}->error('tailf-ned-cisco-ios-xr:interface:' . $@);
            }
            next;
        }

        my $ports = eval {
            my $result = [];
            my $types  = ["Bundle-Ether", "GigabitEthernet", "TenGigE", "FortyGigE", "HundredGigE", "FourHundredGigE"];

            foreach my $type (@$types) {
                my @gb_ports = $dom->findnodes("/cisco-ios-xr:interface/cisco-ios-xr:$type");
                foreach my $port (@gb_ports) {
                    my $port_info = {
                        admin_state => $port->exists('./cisco-ios-xr:shutdown') ? 'down' : 'up',
                        bandwidth   => $port->findvalue('./cisco-ios-xr:speed') || 1000,
                        description => $port->findvalue('./cisco-ios-xr:description') || '',
                        mtu         => $port->findvalue('./cisco-ios-xr:mtu') || 0,
                        name        => $type . $port->findvalue('./cisco-ios-xr:id')
                    };
                    push @$result, $port_info;
                }
            }
            return $result;
        };
        if ($@) {
            warn 'port_info:' . $@;
            $self->{logger}->error('port_info:' . $@);
            next;
        }

        $self->{db}->start_transaction;
        foreach my $data (@$ports) {
            my $port = new OESS::Interface(db => $self->{db}, node => $node->{name}, name => $data->{name});
            if (defined $port) {
                $port->admin_state($data->{admin_state});
                $port->bandwidth($data->{bandwidth});
                $port->description($data->{description});
                $port->mtu($data->{mtu});
                $port->update_db;
            } else {
                warn "Couldn't find interface $node->{name} $data->{name}; Creating interface.";
                $self->{logger}->warn("Couldn't find interface $node->{name} $data->{name}; Creating interface.");

                $port = new OESS::Interface(db => $self->{db}, model => {
                    admin_state => $data->{admin_state},
                    bandwidth => $data->{bandwidth},
                    description => $data->{description},
                    mtu => $data->{mtu},
                    name => $data->{name},
                    operational_state => $data->{admin_state} # Using admin_state as best guess for now
                });

                my ($port_id, $port_err) = $port->create(node_id => $node->{node_id});
                if (defined $port_err) {
                    warn "Couldn't create interface $node->{name} $data->{name}.";
                    $self->{logger}->error("Couldn't create interface $node->{name} $data->{name}.")
                }
            }
        }
        $self->{db}->commit;
    }
    return 1;
}

=head2 link_handler

=cut
sub link_handler {
    my $self = shift;

    # lookup links name and put into index
    my ($links, $links_err) = OESS::DB::Link::fetch_all(db => $self->{db});

    my $links_index = {};
    foreach my $link (@$links) {
        $links_index->{$link->{name}} = $link;
    }

    # get links from nso
    my ($backbones, $err) = $self->{nso}->get_backbones();
    if (defined $err) {
        $self->{logger}->error($err);
        return;
    }

    # lookup nso links in index
    foreach my $bb (@$backbones) {

        my $n = scalar @{$bb->{summary}->{endpoint}};
        if ($n != 2) {
            $self->{logger}->error("Couldn't process link $bb->{name}. Got $n endpoinds but only expected 2.");
            next;
        }

        # Lookup interface ids of backbone edges
        my $eps = [];
        foreach my $ep (@{$bb->{summary}->{endpoint}}) {
            my $id = OESS::DB::Interface::get_interface(
                db        => $self->{db},
                interface => $ep->{'if-full'},
                node      => $ep->{'device'},
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

        # decom all links still in index
        foreach my $name (keys %$links_index) {
            my $link = $links_index->{$name};
            $self->{logger}->info("Decommissioning link $link->{name}.");

            my ($link_id, $link_err) = OESS::DB::Link::update(
                db    => $self->{db},
                model => {
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
    }

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
    $self->device_handler;
    $self->interface_handler;

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
    $self->{connection_timer} = AnyEvent->timer(
        after    => 20,
        interval => 60,
        cb       => sub { $self->connection_handler(@_); }
    );
    $self->{device_timer} = AnyEvent->timer(
        after    => 10,
        interval => 60,
        cb       => sub { $self->device_handler(@_); }
    );
    $self->{interface_timer} = AnyEvent->timer(
        after    =>  60,
        interval => 120,
        cb       => sub { $self->interface_handler(@_); }
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

    foreach my $key (keys %{$self->{nodes}}) {
        my $node = $self->{nodes}->{$key};

        my ($stats, $err) = $self->{nso}->get_vrf_statistics($node->{name});
        if (defined $err) {
            $self->{logger}->error($err);
            next;
        }

        $self->handle_vrf_stats(node => $node, stats => $stats);
    }
}

=head2 handle_vrf_stats

=cut

sub handle_vrf_stats{
    my $self = shift;
    my @params = @_;

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


=head2 stop

=cut
sub stop {
    my $self = shift;
    $self->{logger}->info('Stopping OESS::NSO::Discovery.');
    $self->{dispatcher}->stop_consuming;
}

1;
