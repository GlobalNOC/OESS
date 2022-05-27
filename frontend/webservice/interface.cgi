#!/usr/bin/perl

use strict;
use warnings;

use AnyEvent;
use GRNOC::WebService::Method;
use GRNOC::WebService::Dispatcher;

use OESS::AccessController::Default;
use OESS::Config;
use OESS::DB;
use OESS::DB::ACL;
use OESS::Endpoint;
use OESS::Entity;
use OESS::Interface;
use OESS::RabbitMQ::Client;
use OESS::RabbitMQ::Topic qw(fwdctl_topic_for_node);
use OESS::VRF;
use OESS::Webservice;
use OESS::Workgroup;


my $config = new OESS::Config(config_filename => '/etc/oess/database.xml');
my $db = new OESS::DB(config_obj => $config);
my $ac = new OESS::AccessController::Default(db => $db);
my $svc = new GRNOC::WebService::Dispatcher();


sub register_ro_methods {

    my $method = GRNOC::WebService::Method->new(
        name => "get_available_vlans",
        description => "returns a list of available vlan tags ",
        callback => sub { get_available_vlans(@_) }
        );

    $method->add_input_parameter( name => 'interface_id',
                                  pattern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 1,
                                  description => 'Interface ID to fetch details'
        );
    
    $method->add_input_parameter( name => 'workgroup_id',
                                  pattern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 1,
                                  description => 'Workgroup ID to fetch details'
        );

    $method->add_input_parameter( name => 'vrf_id',
                                  patern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 0,
                                  description => 'VRF ID of the VRF being edited (if one is being edited)');
    
    $method->add_input_parameter( name => 'circuit_id',
                                  patern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 0,
                                  description => 'VRF ID of the VRF being edited (if one is being edited)');

    $svc->register_method($method);

    my $get_interface = GRNOC::WebService::Method->new(
        name        => "get_interface",
        description => "get_interface returns the requested interface",
        callback    => sub { get_interface(@_) }
    );
    $get_interface->add_input_parameter(
        name        => 'interface_id',
        pattern     => $GRNOC::WebService::Regex::INTEGER,
        required    => 1,
        description => 'InterfaceId of interface'
    );
    $svc->register_method($get_interface);

    $method = GRNOC::WebService::Method->new(
        name => "get_interfaces",
        description => "returns a list of interfaces for a node",
        callback => sub { get_interfaces(@_) }
    );
    $method->add_input_parameter(
        name => 'node_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 0,
        description => 'Node ID to fetch details'
     );
    $method->add_input_parameter(
        name => 'workgroup_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 0,
        description => 'Workgroup ID to filter results'
     );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name => "is_vlan_available",
        description => "returns 1 or 0 if the vlan tag is available",
        callback => sub { is_vlan_available(@_) });

    $method->add_input_parameter( name => "interface_id",
                                  pattern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 1,
                                  description => "Interface ID to check and see if VLAN tag is available");
    $method->add_input_parameter( name => 'workgroup_id',
                                  pattern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 1,
                                  description => 'Workgroup ID to fetch details'
        );
    
    $method->add_input_parameter( name => 'vlan',
                                  pattern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 1,
                                  description => 'VLAN to check and see if it is avaialble'
        );
    

    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name => "get_workgroup_interfaces",
        description => "returns a list of available vlan tags ",
        callback => sub { get_workgroup_interfaces(@_) },
        method_deprecated => "This method has been deprecated in favor of interface.cgi?method=get_interfaces."
    );

    $method->add_input_parameter( name => 'workgroup_id',
                                  pattern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 1,
                                  description => 'Workgroup ID to fetch details'
        );
    
    $svc->register_method($method);
}

sub register_rw_methods {
    my $edit_interface = GRNOC::WebService::Method->new(
        name        => "edit_interface",
        description => "edit_interface edits interface interface_id",
        callback    => sub { edit_interface(@_) }
    );
    $edit_interface->add_input_parameter(
        name        => 'interface_id',
        pattern     => $GRNOC::WebService::Regex::INTEGER,
        required    => 1,
        description => 'Identifier used to lookup the interface'
    );
    $edit_interface->add_input_parameter(
        name        => 'workgroup_id',
        pattern     => $GRNOC::WebService::Regex::INTEGER,
        required    => 0,
        description => 'Identifier of workgroup used to grant ownership of interface'
    );
    $edit_interface->add_input_parameter(
        name        => 'mpls_vlan_tag_range',
        pattern     => $GRNOC::WebService::Regex::TEXT,
        required    => 0,
        description => 'Comma separated list of VLAN ranges allowed on this interface'
    );
    $edit_interface->add_input_parameter(
        name        => 'cloud_interconnect_id',
        pattern     => $GRNOC::WebService::Regex::TEXT,
        required    => 0,
        description => 'Physical interconnect ID used by connector'
    );
    $edit_interface->add_input_parameter(
        name        => 'cloud_interconnect_type',
        pattern     => '^(aws-hosted-connection|azure-express-route|gcp-partner-interconnect|oracle-fast-connect|)$',
        required    => 0,
        description => 'Physical interconnect type of connector'
    );
    $svc->register_method($edit_interface);

    my $migrate_interface = GRNOC::WebService::Method->new(
        name        => "migrate_interface",
        description => "moves all entities, connections, and configuration from src_interface_id to dst_interface_id",
        callback    => sub { migrate_interface(@_) }
    );
    $migrate_interface->add_input_parameter(
        name        => 'src_interface_id',
        pattern     => $GRNOC::WebService::Regex::INTEGER,
        required    => 1,
        description => 'Identifier used to lookup the interface'
    );
    $migrate_interface->add_input_parameter(
        name        => 'dst_interface_id',
        pattern     => $GRNOC::WebService::Regex::INTEGER,
        required    => 1,
        description => 'Identifier used to lookup the interface'
    );
    $svc->register_method($migrate_interface);
}

sub get_available_vlans {
    my $method = shift;
    my $params = shift;

    my $interface_id = $params->{'interface_id'}{'value'};
    my $workgroup_id = $params->{'workgroup_id'}{'value'};

    my $vrf_id = $params->{'vrf_id'}{'value'};
    my $circuit_id = $params->{'circuit_id'}{'value'};

    my $interface = OESS::Interface->new(interface_id => $interface_id, db => $db);
    if(!defined($interface)){
        $method->set_error("Unable to build interface $interface_id: " . $db->get_error);
        return;
    }

    my $already_used_vlan;
    if(defined($vrf_id)){
        my $vrf = OESS::VRF->new( vrf_id => $vrf_id, db => $db);
        if(!defined($vrf)){
            $method->set_error("unable to find VRF: $vrf_id");
            return;
        }
        
        foreach my $ep (@{$vrf->endpoints()}){
            if($ep->interface()->interface_id() == $interface_id){
                $already_used_vlan = $ep->tag();
            }
        }
    }
    

    my @allowed_vlans;
    for(my $i=1;$i<=4095;$i++){
        if(defined($already_used_vlan) && $already_used_vlan == $i){
            push(@allowed_vlans,$i);
            next;
        }
        if($interface->vlan_valid( workgroup_id => $workgroup_id, vlan => $i )){
            push(@allowed_vlans,$i);
        }
        
    }

    return {results => {available_vlans => \@allowed_vlans}};
}

sub is_vlan_available {
    my $method = shift;
    my $params = shift;

    my $interface_id = $params->{'interface_id'}{'value'};
    my $workgroup_id = $params->{'workgroup_id'}{'value'};
    my $vlan = $params->{'vlan'}{'value'};

    my $interface = OESS::Interface->new(interface_id => $interface_id, db => $db);
    if(!defined($interface)){
        $method->set_error("Unable to build interface $interface_id: " . $db->get_error);
        return;
    }

    return {results => {allowed => $interface->vlan_valid( workgroup_id => $workgroup_id, vlan => $vlan )}};
}

sub get_workgroup_interfaces {
    my $method = shift;
    my $params = shift;
    my $workgroup_id = $params->{'workgroup_id'}{'value'};
    my $vlan = $params->{'vlan'}{'value'};

    my ($ok, $err) = OESS::DB::User::has_workgroup_access(
        db           => $db,
        username     => $ENV{REMOTE_USER},
        workgroup_id => $params->{workgroup_id}->{value},
        role         => 'read-only'
    );
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $workgroup = OESS::Workgroup->new( workgroup_id => $workgroup_id, db => $db);
    my $interfaces = $workgroup->interfaces();

    my @res;
    foreach my $interface (@$interfaces){
        my $obj = $interface->to_hash();
        my $entity = OESS::Entity->new( interface_id => $interface->interface_id(), db => $db);
        if(defined($entity)){
            $obj->{'entity'} = $entity->name();
            $obj->{'entity_id'} = $entity->entity_id();
        }
        push(@res, $obj);
    }

    return {results => \@res};
}

sub get_interface {
    my $method = shift;
    my $params = shift;

    my $interface = new OESS::Interface(
        db => $db,
        interface_id => $params->{interface_id}{value}
    );
    if (!defined $interface) {
        $method->set_error("Couldn't find interface $params->{interface_id}{value}.");
        return;
    }
    return { results => [ $interface->to_hash ] };
}

sub get_interfaces {
    my $method = shift;
    my $params = shift;

    my $interfaces = OESS::DB::Interface::get_interfaces(
        db => $db,
        node_id => $params->{node_id}{value},
        workgroup_id => $params->{workgroup_id}{value}
    );

    my $results = [];
    foreach my $interface_id (@$interfaces) {
        my $interface = OESS::Interface->new(db => $db, interface_id => $interface_id);
        push @$results, $interface->to_hash;
    }
    return { results => $results };
}

sub edit_interface {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($ok, $access_err) = $user->has_system_access(role => 'normal');
    if (defined $access_err) {
        $method->set_error($access_err);
        return;
    }

    $db->start_transaction;

    my $interface = new OESS::Interface(
        db => $db,
        interface_id => $params->{interface_id}{value}
    );
    if (!defined $interface) {
        $method->set_error("Couldn't find interface $params->{interface_id}{value}.");
        return;
    }

    if ($interface->role eq 'trunk') {
        $method->set_error("Trunk interfaces cannot be modified.");
        return;
    }

    if ($params->{workgroup_id}{is_set} && $params->{workgroup_id}{value} != $interface->workgroup_id) {
        if ($params->{workgroup_id}{value} == -1) {
            # Remove interface from workgroup
            $interface->{workgroup_id} = undef;
            
            my ($ok, $err) = OESS::DB::ACL::remove_all(
                db => $db,
                interface_id => $interface->interface_id
            );
            if (defined $err) {
                $method->set_error($err);
                $db->rollback;
                return;
            }
        }
        elsif (defined $interface->workgroup_id) {
            # Interface is already owned by a workgroup. Preserve all ACLs by default.
            $interface->workgroup_id($params->{workgroup_id}{value});
        }
        else {
            # Add interface to workgroup
            my $acl = new OESS::ACL(
                db => $db,
                model => {
                    workgroup_id  => -1,
                    interface_id  => $interface->interface_id,
                    allow_deny    => 'allow',
                    eval_position => 10,
                    start         => 2,
                    end           => 4094,
                    notes         => 'Default ACL'
                }
            );
            $acl->create;
            $interface->workgroup_id($params->{workgroup_id}{value});
        }
    }

    # We use $obj->{attr} syntax to support setting attribute to undef
    if ($params->{mpls_vlan_tag_range}{is_set}) {
        my ($vlan_tag_range, $err) = OESS::Webservice::validate_vlan_tag_range($params->{mpls_vlan_tag_range}{value});
        if ($err) {
            $method->set_error("mpls_vlan_tag_range: $err");
            $db->rollback;
            return;
        } 
        $interface->{mpls_vlan_tag_range} = $vlan_tag_range;
    }
    if ($params->{cloud_interconnect_id}{is_set}) {
        $interface->{cloud_interconnect_id} = $params->{cloud_interconnect_id}{value};
    }
    if ($params->{cloud_interconnect_type}{is_set}) {
        $interface->{cloud_interconnect_type} = $params->{cloud_interconnect_type}{value};
    }
    $interface->update_db;

    $db->commit;

    return { results => [ $interface->to_hash ] };
}

sub migrate_interface {
    my $method = shift;
    my $params = shift;

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($ok, $access_err) = $user->has_system_access(role => 'normal');
    if (defined $access_err) {
        $method->set_error($access_err);
        return;
    }

    $db->start_transaction();

    # Move configuration
    my $src_interface = new OESS::Interface(
        db => $db,
        interface_id => $params->{src_interface_id}{value}
    );
    if (!defined $src_interface) {
        $method->set_error("Couldn't find source interface $params->{src_interface_id}{value}.");
        return;
    }

    my $dst_interface = new OESS::Interface(
        db => $db,
        interface_id => $params->{dst_interface_id}{value}
    );
    if (!defined $dst_interface) {
        $method->set_error("Couldn't find destination interface $params->{dst_interface_id}{value}.");
        return;
    }

    $dst_interface->cloud_interconnect_id($src_interface->cloud_interconnect_id);
    $dst_interface->cloud_interconnect_type($src_interface->cloud_interconnect_type);
    $dst_interface->workgroup_id($src_interface->workgroup_id);
    my $dst_ok = $dst_interface->update_db();
    if (!defined $dst_ok) {
        $method->set_error("Couldn't update destination interface: " . $db->get_error);
        $db->rollback();
        return;
    }

    $src_interface->{cloud_interconnect_id} = undef;
    $src_interface->{cloud_interconnect_type} = undef;
    $src_interface->{workgroup_id} = undef;
    my $src_ok = $src_interface->update_db();
    if (!defined $src_ok) {
        $method->set_error("Couldn't update source interface: " . $db->get_error);
        $db->rollback();
        return;
    }

    # Move connection endpoints
    my $endpoints_ok = OESS::Endpoint::move_endpoints(
        db => $db,
        new_interface_id  => $params->{dst_interface_id}{value},
        orig_interface_id => $params->{src_interface_id}{value}
    );
    if (!defined $endpoints_ok) {
        $method->set_error("Couldn't move Endpoints: " . $db->get_error);
        $db->rollback();
        return;
    }

    # Move entities
    my $acls = OESS::DB::ACL::fetch_all(
        db => $db,
        interface_id => $params->{src_interface_id}{value}
    );
    foreach my $acl (@$acls) {
        my $obj = OESS::ACL->new(db => $db, model => $acl);
        $obj->interface_id($params->{dst_interface_id}{value});

        my $ok = $obj->update_db();
        if (!defined $ok) {
            $method->set_error("Couldn't move ACLs: $err");
            $db->rollback();
            return;
        }
    }

    $db->commit();

    my $src_node = new OESS::Node(
        db => $db,
        node_id => $src_interface->node_id
    );
    my $dst_node = new OESS::Node(
        db => $db,
        node_id => $dst_interface->node_id
    );
    if ($src_node->controller ne $dst_node->controller) {
        $method->set_error("Interfaces cannot be migrated between controllers, as this would result in Connections with Endpoints on multiple controllers.");
        return;
    }

    my ($topic, $topic_err) = fwdctl_topic_for_node($src_node);
    if (defined $topic_err) {
        $method->set_error($topic_err);
        return;
    }
    my $mq = OESS::RabbitMQ::Client->new(
        topic    => $topic,
        timeout  => 60
    );
    if (!defined $mq) {
        $method->set_error("Couldn't create RabbitMQ client.");
        return;
    }

    my $cv = AnyEvent->condvar;
    $mq->update_cache(
        async_callback => sub {
            my $result = shift;
            $cv->send($result);
        }
    );
    my $result = $cv->recv();
    if (!defined $result) {
        $method->set_error("Error while calling `update_cache` via RabbitMQ.");
        return;
    }
    if (defined $result->{error}) {
        $method->set_error("Error while calling `update_cache`: $result->{error}");
        return;
    }

    return { results => [ { success => $result->{results}->{status} } ] };
}

sub main {
    register_ro_methods();
    register_rw_methods();
    $svc->handle_request();
}

main();
