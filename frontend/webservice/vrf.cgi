#!/usr/bin/perl -I /home/aragusa/OESS/perl-lib/OESS/lib

use strict;
use warnings;

use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use JSON;
use Log::Log4perl;

use GRNOC::WebService::Method;
use GRNOC::WebService::Dispatcher;

use OESS::RabbitMQ::Client;
use OESS::Cloud;
use OESS::Config;
use OESS::DB;
use OESS::DB::Entity;
use OESS::User;
use OESS::VRF;


Log::Log4perl::init_and_watch('/etc/oess/logging.conf',10);

my $config = new OESS::Config();
my $db = OESS::DB->new();
my $svc = GRNOC::WebService::Dispatcher->new();
my $mq = OESS::RabbitMQ::Client->new( topic    => 'OF.FWDCTL.RPC',
                                      timeout  => 120 );

my $log_client = OESS::RabbitMQ::Client->new( topic    => 'OF.FWDCTL.event',
                                              timeout  => 15 );

sub register_ro_methods {
    my $method = GRNOC::WebService::Method->new(
        name => "get_vrf_details",
        description => "Returns the Layer3 Connection identified by vrf_id.",
        callback => sub { get_vrf_details(@_) }
    );
    $method->add_input_parameter(
        name => 'vrf_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
        description => 'Identifier Layer3 Connection to return.'
    );
    $method->add_input_parameter(
        name => 'workgroup_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
        description => 'Identifier of Workgroup used to fetch Layer3 Connections.'
    );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name => 'get_vrfs',
        description => 'Returns a list of Layer3 Connections.',
        callback => sub { get_vrfs(@_) }
    );
    $method->add_input_parameter(
        name => 'workgroup_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
        description => 'Identifier of Workgroup used to fetch Layer3 Connections.'
    );
    $svc->register_method($method);
}

sub register_rw_methods{
    
    my $method = GRNOC::WebService::Method->new(
        name => 'provision',
        description => 'provision a new vrf on the network',
        callback => sub { provision_vrf(@_) });

    $method->add_input_parameter(
        name            => 'vrf_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "If editing an existing VRF specify the ID otherwise leave blank for new VRF."
        );

    $method->add_input_parameter(
        name            => 'skip_cloud_provisioning',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "If editing an existing VRF specify the ID otherwise leave blank for new VRF.",
        default         => 0
    );

    $method->add_input_parameter(
        name            => 'name',
        pattern         => $GRNOC::WebService::Regex::NAME_ID,
        required        => 1,
        description     => "The workgroup_id with permission to build the vrf, the user must be a member of this workgroup."
        );

    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The workgroup_id with permission to build the vrf, the user must be a member of this workgroup."
        );

    #add the required input parameter description
    $method->add_input_parameter(
        name            => 'description',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "The description of the circuit."
        );    
    
    $method->add_input_parameter(
        name            => 'endpoint',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        multiple        => 1,
        description     => "The JSON blob describing all of the endpoints"
    );

    $method->add_input_parameter(
        name            => 'local_asn',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The JSON blob describing all of the endpoints"
    );

    $method->add_input_parameter(
        name            => 'prefix_limit',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        default         => 1000,
        description     => "Maximum prefix limit size for BGP peer routes"
    );

    $svc->register_method($method);
    
    $method = GRNOC::WebService::Method->new(
        name => 'remove',
        description => 'removes a vrf that is on the network',
        callback => sub { remove_vrf(@_) });    
    
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The workgroup_id with permission to build the vrf, the user must be a member of this workgroup."
        );

    $method->add_input_parameter(
        name => 'vrf_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
        description => 'the ID of the VRF to remove from the network');

    $svc->register_method($method);

}

sub get_vrf_details{
    my $method = shift;
    my $params = shift;
    my $ref = shift;

    my $vrf_id = $params->{'vrf_id'}{'value'};

    if ($config->network_type ne 'vpn-mpls') {
        $method->set_error("Support for Layer 3 Connections is currently disabled. Please contact your OESS administrator for more information.");
        return;
    }

    my $user = new OESS::User(db => $db, username =>  $ENV{REMOTE_USER});
    if (!defined $user) {
        $method->set_error("User '$ENV{REMOTE_USER}' is invalid.");
        return;
    }
    $user->load_workgroups;

    my $workgroup = $user->get_workgroup(workgroup_id => $params->{workgroup_id}->{value});
    if (!defined $workgroup && !$user->is_admin) {
        $method->set_error("User '$user->{username}' isn't a member of the specified workgroup.");
        return;
    }

    # If user is an admin and an admin workgroup is selected clear out
    # the workgroup_id; This returns all Connections. Otherwise filter
    # by the passed in workgroup_id. An invalid workgroup_id will
    # simply return nothing.
    if (defined $workgroup && $workgroup->type eq 'admin') {
        $params->{workgroup_id}->{value} = undef;
    }

    my $vrfs = OESS::DB::VRF::get_vrfs(
        db => $db,
        state => 'active',
        vrf_id => $vrf_id,
        workgroup_id => $params->{workgroup_id}->{value}
    );
    if (!defined $vrfs || !defined $vrfs->[0]) {
        $method->set_error("VRF: $vrf_id was not found.");
        return;
    }

    my $vrf = OESS::VRF->new(db => $db, vrf_id => $vrfs->[0]->{vrf_id});
    if (!defined $vrf) {
        $method->set_error("VRF: $vrf_id was not found.");
        return;
    }
    $vrf->load_endpoints;
    foreach my $ep (@{$vrf->endpoints}) {
        $ep->load_peers;
    }
    $vrf->load_users;
    $vrf->load_workgroup;

    return { results => [ $vrf->to_hash ] };
}

sub get_vrfs{
    my $method = shift;
    my $params = shift;
    my $ref = shift;

    if ($config->network_type ne 'vpn-mpls') {
        $method->set_error("Support for Layer 3 Connections is currently disabled. Please contact your OESS administrator for more information.");
        return;
    }

    my $user = new OESS::User(db => $db, username =>  $ENV{REMOTE_USER});
    if (!defined $user) {
        $method->set_error("User '$ENV{REMOTE_USER}' is invalid.");
        return;
    }
    $user->load_workgroups;

    my $workgroup = $user->get_workgroup(workgroup_id => $params->{workgroup_id}->{value});
    if (!defined $workgroup && !$user->is_admin) {
        $method->set_error("User '$user->{username}' isn't a member of the specified workgroup.");
        return;
    }

    # If user is an admin and an admin workgroup is selected clear out
    # the workgroup_id; This returns all Connections. Otherwise filter
    # by the passed in workgroup_id. An invalid workgroup_id will
    # simply return nothing.
    if (defined $workgroup && $workgroup->type eq 'admin') {
        $params->{workgroup_id}->{value} = undef;
    }

    my $vrfs = OESS::DB::VRF::get_vrfs(
        db => $db,
        workgroup_id => $params->{workgroup_id}->{value},
        state => 'active'
    );

    my $result = [];
    foreach my $vrf (@$vrfs) {
        my $r = OESS::VRF->new(db => $db, vrf_id => $vrf->{vrf_id});
        next if (!defined $r);
        $r->load_endpoints;
        foreach my $ep (@{$r->endpoints}) {
            $ep->load_peers;
        }
        $r->load_users;
        $r->load_workgroup;
        push @$result, $r->to_hash();
    }
    return $result;
}

sub provision_vrf{
    my $method = shift;
    my $params = shift;

    if ($config->network_type ne 'vpn-mpls') {
        $method->set_error("Support for Layer 3 Connections is currently disabled. Please contact your OESS administrator for more information.");
        return;
    }

    my $user = new OESS::User(db => $db, username => $ENV{REMOTE_USER});
    if (!defined $user) {
        $method->set_error("User '$ENV{REMOTE_USER}' is invalid.");
        return;
    }
    if ($user->type eq 'read-only') {
        $method->set_error("User '$user->{username}' is read-only.");
        return;
    }

    my $model = {};
    $model->{'description'} = $params->{'description'}{'value'};
    $model->{'prefix_limit'} = $params->{'prefix_limit'}{'value'};
    $model->{'workgroup_id'} = $params->{'workgroup_id'}{'value'};
    $model->{'vrf_id'} = $params->{'vrf_id'}{'value'} || undef;
    $model->{'name'} = $params->{'name'}{'value'};
    $model->{'provision_time'} = $params->{'provision_time'}{'value'};
    $model->{'remove_time'} = $params->{'provision_time'}{'value'};
    $model->{'last_modified'} = $params->{'provision_time'}{'value'};
    $model->{'endpoints'} = ();

    # User must be in workgroup or an admin to continue
    if (!$user->in_workgroup($model->{'workgroup_id'}) && !$user->is_admin()){
        $method->set_error("User is not in workgroup $model->{workgroup_id}.");
        return;
    }

    if (@{$params->{endpoint}->{value}} < 2) {
        $method->set_error("Couldn't create L3Connection: Connection requires at least two Endpoints.");
        return;
    }

    # Modified VRFs should already have selected the appropriate
    # endpoints for any of their cloud connections. This has not been
    # been done for new VRFs.
    my $selected_endpoints = [];
    my $db = OESS::DB->new;
    $db->start_transaction;

    my $vrf = undef;
    if (defined $model->{'vrf_id'} && $model->{'vrf_id'} != -1) {
        $vrf = OESS::VRF->new(db => $db, vrf_id => $model->{'vrf_id'});
        if (!defined $vrf) {
            $method->set_error("Couldn't load VRF");
            $db->rollback;
            return;
        }

        $vrf->load_endpoints;
        $vrf->last_modified_by($user);
        $vrf->update;
    } else {
        $model->{created_by_id} = $user->user_id;
        $model->{last_modified_by_id} = $user->user_id;
        $model->{workgroup_id} = $params->{workgroup_id}->{value};
        $vrf = OESS::VRF->new(db => $db, model => $model);
        my ($vrf_id, $vrf_err) = $vrf->create;
        if (defined $vrf_err) {
            $method->set_error("Couldn't create VRF: $vrf_err");
            $db->rollback;
            return;
        }
    }

    # Use $peerings to validate a local address isn't specified twice
    # on the same interface. Cloud peerings are provided/overwritten
    # with sane defaults.
    my $last_octet = 2;
    my $peerings = {};


    # Hash to track which endpoints have been updated and which shall
    # be removed.
    my $endpoints = {};
    foreach my $ep (@{$vrf->endpoints}) {
        $endpoints->{$ep->vrf_endpoint_id} = $ep;
    }

    my $add_endpoints = [];
    my $del_endpoints = [];

    foreach my $value (@{$params->{endpoint}{value}}) {
        my $ep;
        eval{
            $ep = decode_json($value);
        };
        if ($@) {
            $method->set_error("Cannot decode endpoint: $@");
            return;
        }

        if (!defined $ep->{vrf_endpoint_id}) {
            my $entity;
            my $interface;

            if (defined $ep->{node} && defined $ep->{interface}) {
                $interface = new OESS::Interface(
                    db => $db,
                    name => $ep->{interface},
                    node => $ep->{node}
                );
            }
            if (defined $interface && (!defined $interface->{cloud_interconnect_type} || $interface->{cloud_interconnect_type} eq 'aws-hosted-connection')) {
                # Continue
            } else {
                $entity = new OESS::Entity(db => $db, name => $ep->{entity});
                $interface = $entity->select_interface(
                    inner_tag    => $ep->{inner_tag},
                    tag          => $ep->{tag},
                    workgroup_id => $model->{workgroup_id},
                    cloud_account_id => $ep->{cloud_account_id}
                );
            }
            if (!defined $interface) {
                $method->set_error("Cannot find a valid Interface for $ep->{entity}.");
                $db->rollback;
                return;
            }

            my $valid_bandwidth = $interface->is_bandwidth_valid(bandwidth => $ep->{bandwidth});
            if (!$valid_bandwidth) {
                $method->set_error("Couldn't create VRF: Specified bandwidth is invalid for $ep->{entity}.");
                $db->rollback;
                return;
            }

            $ep->{type}         = 'vrf';
            $ep->{entity_id}    = $entity->{entity_id};
            $ep->{interface}    = $interface->{name};
            $ep->{interface_id} = $interface->{interface_id};
            $ep->{node}         = $interface->{node}->{name};
            $ep->{node_id}      = $interface->{node}->{node_id};
            $ep->{cloud_interconnect_id}   = $interface->cloud_interconnect_id;
            $ep->{cloud_interconnect_type} = $interface->cloud_interconnect_type;

            if ($ep->{cloud_interconnect_type} eq 'aws-hosted-connection') {
                if (defined $ep->{cloud_gateway_type} && $ep->{cloud_gateway_type} eq 'transit') {
                    $ep->{mtu} = (!defined $ep->{jumbo} || $ep->{jumbo} == 1) ? 8500 : 1500;
                } else {
                    $ep->{mtu} = (!defined $ep->{jumbo} || $ep->{jumbo} == 1) ? 9001 : 1500;
                }
            } elsif ($ep->{cloud_interconnect_type} eq 'aws-hosted-vinterface') {
                $ep->{mtu} = (!defined $ep->{jumbo} || $ep->{jumbo} == 1) ? 9001 : 1500;
            } elsif ($ep->{cloud_interconnect_type} eq 'gcp-partner-inerconnect') {
                $ep->{mtu} = 1440;
            } elsif ($ep->{cloud_interconnect_type} eq 'azure-express-route') {
                $ep->{mtu} = 1500;
            } else {
                $ep->{mtu} = (!defined $ep->{jumbo} || $ep->{jumbo} == 1) ? 9000 : 1500;
            }

            my $endpoint = new OESS::Endpoint(db => $db, model => $ep);
            my ($ep_id, $ep_err) = $endpoint->create(
                vrf_id => $vrf->vrf_id,
                workgroup_id => $model->{workgroup_id}
            );
            if (defined $ep_err) {
                $method->set_error("Couldn't create VRF: $ep_err");
                $db->rollback;
                return;
            }
            $vrf->add_endpoint($endpoint);
            push @$add_endpoints, $endpoint;

            foreach my $peering (@{$ep->{peers}}) {
                if ($interface->cloud_interconnect_type eq 'azure-express-route') {
                    my $peer;
                    if ($endpoint->cloud_interconnect_id =~ /PRI/) {
                        # pri_prefix: '192.168.100.248/30';
                        $peer = new OESS::Peer(
                            db => $db,
                            model => {
                                peer_asn => 12076,
                                md5_key => '',
                                local_ip => '192.168.100.249/30',
                                peer_ip  => '192.168.100.250/30',
                                version  => 4
                            }
                        );
                    } else {
                        # sec_prefix: '192.168.100.252/30';
                        $peer = new OESS::Peer(
                            db => $db,
                            model => {
                                peer_asn => 12076,
                                md5_key => '',
                                local_ip => '192.168.100.253/30',
                                peer_ip  => '192.168.100.254/30',
                                version  => 4
                            }
                        );
                    }

                    my ($peer_id, $peer_err) = $peer->create(vrf_ep_id => $endpoint->vrf_endpoint_id);
                    if (defined $peer_err) {
                        $method->set_error($peer_err);
                        $db->rollback;
                        return;
                    }
                    $endpoint->add_peer($peer);
                    next;
                }

                if (defined $peerings->{"$endpoint->{node} $endpoint->{interface} $peering->{local_ip}"}) {
                    $method->set_error("Cannot have duplicate local addresses on an interface.");
                    $db->rollback;
                    return;
                }

                # User defined or pre-defined (eg. azure) peering
                if ($peering->{local_ip}) {
                    my $peer = new OESS::Peer(db => $db, model => $peering);
                    my ($peer_id, $peer_err) = $peer->create(vrf_ep_id => $endpoint->vrf_endpoint_id);
                    if (defined $peer_err) {
                        $method->set_error($peer_err);
                        $db->rollback;
                        return;
                    }
                    $endpoint->add_peer($peer);

                    $peerings->{"$endpoint->{node} $endpoint->{interface} $peering->{local_ip}"} = 1;
                    next;
                }

                # Peerings not auto-generated for non-cloud endpoints
                if (defined $endpoint->{cloud_account_id} && $endpoint->{cloud_account_id} eq '') {
                    next;
                }
                if (!defined $endpoint->{cloud_account_id}) {
                    next;
                }

                $peering->{peer_asn} = (!defined $peering->{peer_asn} || $peering->{peer_asn} eq '') ? 64512 : $peering->{peering_asn};
                $peering->{md5_key} = (!defined $peering->{md5_key} || $peering->{md5_key} eq '') ? md5_hex(rand) : $peering->{md5_key};
                if ($peering->{version} == 4) {
                    $peering->{local_ip} = '172.31.254.' . $last_octet . '/31';
                    $peering->{peer_ip}  = '172.31.254.' . ($last_octet + 1) . '/31';
                } else {
                    $peering->{local_ip} = 'fd28:221e:28fa:61d3::' . $last_octet . '/127';
                    $peering->{peer_ip}  = 'fd28:221e:28fa:61d3::' . ($last_octet + 1) . '/127';
                }

                # Assuming we use .2 and .3 the first time around. We
                # can use .4 and .5 on the next peering.
                $last_octet += 2;
                $peerings->{"$endpoint->{node} $endpoint->{interface} $peering->{local_ip}"} = 1;

                my $peer = new OESS::Peer(db => $db, model => $peering);
                my ($peer_id, $peer_err) = $peer->create(vrf_ep_id => $endpoint->vrf_endpoint_id);
                if (defined $peer_err) {
                    $method->set_error($peer_err);
                    $db->rollback;
                    return;
                }
                $endpoint->add_peer($peer);
            }

        } else {
            my $endpoint = $vrf->get_endpoint(vrf_ep_id => $ep->{vrf_endpoint_id});

            $endpoint->bandwidth($ep->{bandwidth});
            $endpoint->inner_tag($ep->{inner_tag});
            $endpoint->tag($ep->{tag});

            if ($endpoint->cloud_interconnect_type eq 'aws-hosted-connection') {
                if (defined $ep->{cloud_gateway_type} && $ep->{cloud_gateway_type} eq 'transit') {
                    $endpoint->mtu((!defined $ep->{jumbo} || $ep->{jumbo} == 1) ? 8500 : 1500);
                } else {
                    $endpoint->mtu((!defined $ep->{jumbo} || $ep->{jumbo} == 1) ? 9001 : 1500);
                }
            } elsif ($endpoint->cloud_interconnect_type eq 'aws-hosted-vinterface') {
                $endpoint->mtu((!defined $ep->{jumbo} || $ep->{jumbo} == 1) ? 9001 : 1500);
            } elsif ($endpoint->cloud_interconnect_type eq 'gcp-partner-inerconnect') {
                $endpoint->mtu(1440);
            } elsif ($endpoint->cloud_interconnect_type eq 'azure-express-route') {
                $endpoint->mtu(1500);
            } else {
                $endpoint->mtu((!defined $ep->{jumbo} || $ep->{jumbo} == 1) ? 9000 : 1500);
            }

            $endpoint->load_peers;

            # Hash to track which peers have been updated and which
            # shall be removed.
            my $peers = {};
            foreach my $peer (@{$endpoint->peers}) {
                $peers->{$peer->vrf_ep_peer_id} = $peer;
            }

            foreach my $peering (@{$ep->{peers}}) {
                if (!defined $peering->{vrf_ep_peer_id}) {

                    if (defined $peerings->{"$endpoint->{node} $endpoint->{interface} $peering->{local_ip}"}) {
                        $method->set_error("Cannot have duplicate local addresses on an interface.");
                        return;
                    }

                    # User defined or pre-defined (eg. azure) peering
                    if ($peering->{local_ip}) {
                        my $peer = new OESS::Peer(db => $db, model => $peering);
                        my ($peer_id, $peer_err) = $peer->create(vrf_ep_id => $endpoint->vrf_endpoint_id);
                        if (defined $peer_err) {
                            $method->set_error($peer_err);
                            $db->rollback;
                            return;
                        }
                        $endpoint->add_peer($peer);

                        $peerings->{"$endpoint->{node} $endpoint->{interface} $peering->{local_ip}"} = 1;
                        next;
                    }

                    # Peerings not auto-generated for non-cloud endpoints
                    if (defined $endpoint->{cloud_account_id} && $endpoint->{cloud_account_id} eq '') {
                        next;
                    }
                    if (!defined $endpoint->{cloud_account_id}) {
                        next;
                    }

                    $peering->{peer_asn} = (!defined $peering->{peer_asn} || $peering->{peer_asn} eq '') ? 64512 : $peering->{peering_asn};
                    $peering->{md5_key} = (!defined $peering->{md5_key} || $peering->{md5_key} eq '') ? md5_hex(rand) : $peering->{md5_key};
                    if ($peering->{version} == 4) {
                        $peering->{local_ip} = '172.31.254.' . $last_octet . '/31';
                        $peering->{peer_ip}  = '172.31.254.' . ($last_octet + 1) . '/31';
                    } else {
                        $peering->{local_ip} = 'fd28:221e:28fa:61d3::' . $last_octet . '/127';
                        $peering->{peer_ip}  = 'fd28:221e:28fa:61d3::' . ($last_octet + 1) . '/127';
                    }

                    # Assuming we use .2 and .3 the first time around. We
                    # can use .4 and .5 on the next peering.
                    $last_octet += 2;
                    $peerings->{"$endpoint->{node} $endpoint->{interface} $peering->{local_ip}"} = 1;

                    my $peer = new OESS::Peer(db => $db, model => $peering);
                    my ($peer_id, $peer_err) = $peer->create(vrf_ep_id => $endpoint->vrf_endpoint_id);
                    if (defined $peer_err) {
                        $method->set_error($peer_err);
                        $db->rollback;
                        return;
                    }
                    $endpoint->add_peer($peer);
                }
                else {
                    my $obj = $endpoint->get_peer(vrf_ep_peer_id => $peering->{vrf_ep_peer_id});
                    if (!defined $obj) {
                        warn 'Unknown vrf_ep_peer_id specified.';
                        next;
                    }

                    $obj->peer_ip($peering->{peer_ip});
                    $obj->peer_asn($peering->{peer_asn});
                    $obj->md5_key($peering->{md5_key});
                    $obj->local_ip($peering->{local_ip});

                    my $obj_err = $obj->update;
                    if (defined $obj_err) {
                        $method->set_error($obj_err);
                        $db->rollback;
                        return;
                    }

                    delete $peers->{$obj->vrf_ep_peer_id};
                }
            }

            foreach my $key (keys %$peers) {
                my $peer = $peers->{$key};
                $peer->decom;
                $endpoint->remove_peer($peer->{vrf_ep_peer_id});
            }

            delete $endpoints->{$endpoint->vrf_endpoint_id};
        }
    }

    foreach my $key (keys %$endpoints) {
        my $endpoint = $endpoints->{$key};
        my $rm_err = $endpoint->remove;
        if (defined $rm_err) {
            $method->set_error($rm_err);
            $db->rollback;
            return;
        }
        $vrf->remove_endpoint($endpoint->vrf_endpoint_id);
        push @$del_endpoints, $endpoint;
    }

    if (!$params->{skip_cloud_provisioning}{value}) {
        eval {
            OESS::Cloud::cleanup_endpoints($del_endpoints);
            OESS::Cloud::setup_endpoints($vrf->name, $add_endpoints);

            foreach my $ep (@{$vrf->endpoints}) {
                # It's expected that layer2 connections to azure pass
                # all QnQ tagged traffic directly to the customer
                # edge; All inner tagged traffic should be passed
                # transparently. This is not the case for l3conns
                # which should match specifically on the qnq tag to
                # ensure proper peerings.
                if ($ep->{cloud_interconnect_type} eq 'azure-express-route') {
                    # We do nothing here as the QinQ tags have already
                    # been selected and will not change for updates.
                }

                my $update_err = $ep->update_db;
                die $update_err if (defined $update_err);
            }
        };
        if ($@) {
            $method->set_error("$@");
            $db->rollback;
            return;
        }
    }

    # warn Dumper($vrf->to_hash);
    # $db->rollback;
    # return { error => 1, error_text => 'lulz' };
    # $db->commit;

    my $vrf_id = $vrf->vrf_id;
    if ($vrf_id == -1) {
        $method->set_error('error creating VRF: ' . $vrf->error());
        return;
    }

    my $res = undef;
    my $type = 'provisioned';
    my $reason = "Created by $ENV{'REMOTE_USER'}";

    if (defined $model->{'vrf_id'} && $model->{'vrf_id'} != -1) {
        # $res = vrf_del(method => $method, vrf_id => $vrf_id);

        # $db->commit;
        # _update_cache(vrf_id => $vrf_id);

        # $res = vrf_add(method => $method, vrf_id => $vrf_id);

        # Database is updated with latest version of the
        # connection. FWDCTL passes cached value (dirty) to switch
        # process along with the value from the db to ensure all
        # endpoints are properly cleaned up.
        $db->commit;
        $res = vrf_modify(method => $method, vrf_id => $vrf_id);
        warn Dumper($res);
        _update_cache(vrf_id => $vrf_id);

        $type = 'modified';
        $reason = "Updated by $ENV{'REMOTE_USER'}";
    } else {
        $db->commit;
        _update_cache(vrf_id => $vrf_id);

        $res = vrf_add(method => $method, vrf_id => $vrf_id);
    }

    eval {
        $log_client->vrf_notification(
            type     => $type,
            reason   => $reason,
            vrf      => $vrf->vrf_id,
            no_reply => 1
        );
    };

    return {results => $res};
}

sub remove_vrf {
    my $method = shift;
    my $params = shift;
    my $ref = shift;

    if ($config->network_type ne 'vpn-mpls') {
        $method->set_error("Support for Layer 3 Connections is currently disabled. Please contact your OESS administrator for more information.");
        return;
    }

    $db->start_transaction;

    my $model = {};
    my $user = new OESS::User(db => $db, username => $ENV{REMOTE_USER});
    if (!defined $user) {
        $method->set_error("User '$ENV{REMOTE_USER}' is invalid.");
        return;
    }
    if ($user->type eq 'read-only') {
        $method->set_error("User '$user->{username}' is read-only.");
        return;
    }

    my $wg = $params->{'workgroup_id'}{'value'};
    my $vrf_id = $params->{'vrf_id'}{'value'} || undef;

    my $vrf = OESS::VRF->new(db => $db, vrf_id => $vrf_id);
    if(!defined($vrf)){
        $method->set_error("Unable to find VRF: " . $vrf_id);
        return {success => 0};
    }
    $vrf->load_endpoints;
    $vrf->load_workgroup;
    $vrf->load_users;

    my $result;
    if(!$user->in_workgroup( $wg) && !$user->is_admin()){
        $method->set_error("User " . $ENV{'REMOTE_USER'} . " is not in workgroup");
        return {success => 0};
    }

    eval {
        OESS::Cloud::cleanup_endpoints($vrf->endpoints);
    };
    if ($@) {
        $method->set_error("$@");
        return;
    }

    my $res = vrf_del(method => $method, vrf_id => $vrf->vrf_id);

    $vrf->decom(user_id => $user->user_id);
    $db->commit;

    _update_cache(vrf_id => $vrf->vrf_id);

    eval {
        $log_client->vrf_notification(
            type     => "removed",
            reason   => "Removed by $ENV{REMOTE_USER}",
            vrf      => $vrf->vrf_id,
            no_reply => 1
        );
    };

    return {results => $res};
}

sub vrf_add{
    my %params = @_;
    my $vrf_id = $params{'vrf_id'};
    my $method = $params{'method'};
    $mq->{'topic'} = 'MPLS.FWDCTL.RPC';
    
    my $cv = AnyEvent->condvar;

    warn "_send_vrf_add_command: Calling addVrf on vrf $vrf_id";
    $mq->addVrf(vrf_id => int($vrf_id), async_callback => sub {
        my $result = shift;
        $cv->send($result);
    });
    
    my $result = $cv->recv();
    
    if (defined $result->{'error'} || !defined $result->{'results'}){
        if (defined $result->{'error'}) {
            $method->set_error($result->{'error'});
        } else {
            $method->set_error("Did not get response from addVRF.");
        }
        return {success => 0, vrf_id => $vrf_id};
    }

    return {success => 1, vrf_id => $vrf_id};
}

sub vrf_del{
    my %params = @_;
    my $vrf_id = $params{'vrf_id'};
    my $method = $params{'method'};
    $mq->{'topic'} = 'MPLS.FWDCTL.RPC';

    my $cv = AnyEvent->condvar;

    warn "_send_vrf_add_command: Calling delVrf on vrf $vrf_id";
    $mq->delVrf(vrf_id => int($vrf_id), async_callback => sub {
        my $result = shift;
        $cv->send($result);
    });
    
    my $result = $cv->recv();
    
    if (defined $result->{'error'} || !defined $result->{'results'}){
        if (defined $result->{'error'}) {
            $method->set_error($result->{'error'});
        } else {
            $method->set_error("Did not get response from delVRF.");
        }
        return {success => 0, vrf_id => $vrf_id};
    }
    
    return {success => 1, vrf_id => $vrf_id};
}

sub vrf_modify{
    my %params = @_;
    my $vrf_id = $params{vrf_id};
    my $method = $params{method};

    $mq->{topic} = 'MPLS.FWDCTL.RPC';

    my $cv = AnyEvent->condvar;

    warn "_send_vrf_modify_command: Calling modifyVrf on vrf $vrf_id";
    $mq->modifyVrf(vrf_id => int($vrf_id), async_callback => sub {
        my $result = shift;
        $cv->send($result);
    });

    my $result = $cv->recv;
    if (defined $result->{error} || !defined $result->{results}) {
        if (defined $result->{error}) {
            $method->set_error($result->{error});
        } else {
            $method->set_error("Did not get response from modifyVRF.");
        }
        return {success => 0, vrf_id => $vrf_id};
    }

    return {success => 1, vrf_id => $vrf_id};
}

sub _update_cache{
    my %args = @_;

    if(!defined($args{'vrf_id'})){
        $args{'vrf_id'} = -1;
    }

    my $err = undef;

    if (!defined $mq) {
        $err = "Couldn't create RabbitMQ client.";
        return;
    } else {
        $mq->{'topic'} = 'MPLS.FWDCTL.RPC';
    }
    my $cv = AnyEvent->condvar;
    $mq->update_cache(vrf_id => $args{'vrf_id'},
                      async_callback => sub {
                          my $result = shift;
                          $cv->send($result);
                      });

    my $result = $cv->recv();

    if (!defined $result) {
        warn "Error occurred while calling update_cache: Couldn't contact MPLS.FWDCTL via RabbitMQ.";
        return undef;
    }
    if (defined $result->{'error'}) {
        warn "Error occurred while calling update_cache: $result->{'error'}";
        return undef;
    }
    if (defined $result->{'results'}->{'error'}) {
        warn "Error occured while calling update_cache: " . $result->{'results'}->{'error'};
        return undef;
    }

    return $result->{'results'}->{'status'};
}


sub main{

    register_ro_methods();
    register_rw_methods();
    $svc->handle_request();
}

main();
