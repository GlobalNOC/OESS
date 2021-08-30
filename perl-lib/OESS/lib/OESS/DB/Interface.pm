#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::Interface;

use OESS::DB::ACL;

use OESS::ACL;
use OESS::Node;

use OESS::DB::Node;

use Data::Dumper;

=head2 fetch

=cut
sub fetch{
    my %params = @_;
    my $db = $params{'db'};

    my $status = $params{'status'} || 'active';

    my $interface_id = $params{'interface_id'};
    my $cloud_interconnect_id = $params{'cloud_interconnect_id'};

    my $params = [];
    my $values = [];

    if (defined $params{interface_id}) {
        push @$params, 'interface.interface_id=?';
        push @$values, $params{interface_id};
    }
    if (defined $params{cloud_interconnect_id}) {
        push @$params, 'interface.cloud_interconnect_id=?';
        push @$values, $params{cloud_interconnect_id};
    }
    my $where = (@$params > 0) ? 'WHERE ' . join(' AND ', @$params) : 'WHERE 1 ';


    my $interface = $db->execute_query(
        "select *, interface_instantiation.capacity_mbps as bandwidth, interface_instantiation.mtu_bytes as mtu
         from interface
         join interface_instantiation on interface.interface_id=interface_instantiation.interface_id and interface_instantiation.end_epoch=-1
         $where",
        $values
    );

    return if (!defined($interface) || !defined($interface->[0]));

    $interface = $interface->[0];

    my $acl_models = OESS::DB::ACL::fetch_all(db => $db, interface_id => $interface_id);
    my $acls = [];
    foreach my $model (@$acl_models) {
        my $acl = OESS::ACL->new(db => $db, model => $model);
        push @$acls, $acl;
    }


    my $l2_utilized_bandwidth = $db->execute_query(
        "select sum(bandwidth) as utilized_bandwidth from circuit_edge_interface_membership where interface_id=? and end_epoch=-1",
        [$interface_id]
    );
    if (!defined $l2_utilized_bandwidth || !defined $l2_utilized_bandwidth->[0]) {
        warn "Couldn't get utilized bandwidth on interface $interface_id.";
        return;
    }
    $l2_utilized_bandwidth = (defined $l2_utilized_bandwidth->[0]->{utilized_bandwidth}) ? $l2_utilized_bandwidth->[0]->{utilized_bandwidth} : 0;

    my $l3_utilized_bandwidth = $db->execute_query(
        "select sum(bandwidth) as utilized_bandwidth from vrf_ep where interface_id=? and state='active'",
        [$interface_id]
    );
    if (!defined $l3_utilized_bandwidth || !defined $l3_utilized_bandwidth->[0]) {
        warn "Couldn't get utilized bandwidth on interface $interface_id.";
        return;
    }
    $l3_utilized_bandwidth = (defined $l3_utilized_bandwidth->[0]->{utilized_bandwidth}) ? $l3_utilized_bandwidth->[0]->{utilized_bandwidth} : 0;

    my $node = OESS::Node->new( db => $db, node_id => $interface->{'node_id'});

    my $in_use = OESS::DB::Interface::vrf_vlans_in_use(db => $db, interface_id => $interface_id );

    push(@{$in_use},@{OESS::DB::Interface::circuit_vlans_in_use(db => $db, interface_id => $interface_id)});

    
    my $provisionable_bandwidth;
    if ($interface->{cloud_interconnect_type} eq 'azure-express-route'){
       $provisionable_bandwidth = $interface->{bandwidth}*4;
    } elsif (defined $interface->{cloud_interconnect_type}){
       $provisionable_bandwidth = $interface->{bandwidth};
    }

    return {
        interface_id => $interface->{'interface_id'},
        cloud_interconnect_type => $interface->{'cloud_interconnect_type'},
        cloud_interconnect_id => $interface->{'cloud_interconnect_id'},
        name => $interface->{'name'},
        role => $interface->{'role'},
        description => $interface->{'description'},
        operational_state => $interface->{'operational_state'},
        node => $node,
        vlan_tag_range => $interface->{'vlan_tag_range'},
        mpls_vlan_tag_range => $interface->{'mpls_vlan_tag_range'},
        workgroup_id => $interface->{'workgroup_id'},
        acls => $acls,
        used_vlans => $in_use,
        bandwidth => $interface->{bandwidth},
        provisionable_bandwidth => $provisionable_bandwidth,
        utilized_bandwidth => $l2_utilized_bandwidth + $l3_utilized_bandwidth,
        mtu => $interface->{mtu},
        admin_state => $interface->{admin_state},
        node_id => $interface->{node_id}
    };
}

=head2 get_interface

=cut
sub get_interface{
    my %params = @_;
    
    my $db = $params{'db'};
    my $interface_name= $params{'interface'};
    my $node_name = $params{'node'};
    
    my $interface = $db->execute_query("select interface_id from interface where name=? and node_id=(select node_id from node where name=?)",[$interface_name, $node_name]);

    if(!defined($interface) || !defined($interface->[0])){
        return;
    }

    return $interface->[0]->{'interface_id'};
}

=head2 get_interfaces

    my $acl = OESS::DB::Interface::get_interfaces(
        db => $conn,
        cloud_interconnect_id => 1, # Optional
        node_id               => 1, # Optional
        workgroup_id          => 1  # Optional
    );

get_interfaces returns a list of all Interfaces from the database
filtered by the provided arguments.

=cut
sub get_interfaces{
    my $args = {
        db => undef,
        cloud_interconnect_id => undef,
        node_id => undef,
        workgroup_id => undef,
        @_
    };

    my $db = $args->{db};

    my $params = [];
    my $values = [];

    if (defined $args->{node_id}) {
        push @$params, "node_id=?";
        push @$values, $args->{node_id};
    }
    if (defined $args->{workgroup_id}) {
        push @$params, "workgroup_id=?";
        push @$values, $args->{workgroup_id};
    }
    if (defined $args->{cloud_interconnect_id}) {
        push @$params, "cloud_interconnect_id=?";
        push @$values, $args->{cloud_interconnect_id};
    }

    my $where = (@$params > 0) ? 'where ' . join(' and ', @$params) : '';

    my $interfaces = $db->execute_query("select interface_id from interface $where", $values);

    my @ints;
    foreach my $int (@$interfaces) {
        push(@ints, $int->{'interface_id'});
    }

    return \@ints;
}

=head2 get_acls

=cut
sub get_acls{
    my %params = @_;

    my $db = $params{'db'};
    my $interface_id = $params{'interface_id'};

    my $acls = $db->execute_query("select * from interface_acl where interface_id = ?",[$interface_id]);
    return $acls;
}

=head2 move_acls

move_acls transfers all ACLs from src_interface_id to
dst_interface_id.

    my $err = move_acls(
        db => $db,
        src_interface_id => 123,
        dst_interface_id => 456
    );
    die $err if defined $err;

=cut
sub move_acls {
    my $args = {
        db => undef,
        dst_interface_id => undef,
        src_interface_id => undef,
        @_
    };

    return 'Required argument `db` is missing.' if !defined $args->{db};
    return 'Required argument `dst_interface_id` is missing.' if !defined $args->{dst_interface_id};
    return 'Required argument `src_interface_id` is missing.' if !defined $args->{src_interface_id};

    my $ok = $args->{db}->execute_query(
        "UPDATE interface_acl SET interface_id=? WHERE interface_acl.interface_id=?",
        [$args->{dst_interface_id}, $args->{src_interface_id}]
    );
    return $args->{db}->get_error if !defined $ok;

    return;
}

=head2 move_configuration

move_configuration transfers all ACLs from src_interface_id to
dst_interface_id.

    my $err = move_acls(
        db => $db,
        src_interface_id => 123,
        dst_interface_id => 456
    );
    die $err if defined $err;

=cut
sub move_configuration {
    my $args = {
        db => undef,
        dst_interface_id => undef,
        src_interface_id => undef,
        @_
    };

    return 'Required argument `db` is missing.' if !defined $args->{db};
    return 'Required argument `dst_interface_id` is missing.' if !defined $args->{dst_interface_id};
    return 'Required argument `src_interface_id` is missing.' if !defined $args->{src_interface_id};

    my $intf = fetch(
        db => $args->{db},
        interface_id => $args->{src_interface_id}
    );
    return "Couldn't find source interface $args->{src_interface_id}." if !defined $intf;
    my $dintf = fetch(
        db => $args->{db},
        interface_id => $args->{dst_interface_id}
    );
    return "Couldn't find destination interface $args->{dst_interface_id}." if !defined $dintf;

    my $q1 = "
        UPDATE interface
        SET cloud_interconnect_id=DEFAULT,cloud_interconnect_type=DEFAULT,description=?,
            vlan_tag_range=DEFAULT,mpls_vlan_tag_range=DEFAULT,workgroup_id=DEFAULT
        WHERE interface.interface_id=?
    ";

    my $ok = $args->{db}->execute_query(
        $q1,
        [
            $intf->{name},
            $args->{src_interface_id},
        ]
    );
    return $args->{db}->get_error if !defined $ok;

    my $q2 = "
        UPDATE interface
        SET cloud_interconnect_id=?,cloud_interconnect_type=?,description=?,
            vlan_tag_range=?,mpls_vlan_tag_range=?,workgroup_id=?
        WHERE interface.interface_id=?
    ";
    $ok = $args->{db}->execute_query(
        $q2,
        [
            $intf->{cloud_interconnect_id},
            $intf->{cloud_interconnect_type},
            $intf->{description},
            $intf->{vlan_tag_range},
            $intf->{mpls_vlan_tag_range},
            $intf->{workgroup_id},
            $args->{dst_interface_id},
        ]
    );
    return $args->{db}->get_error if !defined $ok;

    return;
}

=head2 vrf_vlans_in_use

=cut
sub vrf_vlans_in_use{
    my %params = @_;
    my $db = $params{'db'};
    my $interface_id = $params{'interface_id'};

    my $vlan_tags = $db->execute_query("select vrf_ep.tag from vrf_ep join vrf on vrf_ep.vrf_id = vrf.vrf_id where vrf.state = 'active' and vrf_ep.state = 'active' and vrf_ep.interface_id = ?",[$interface_id]);
    
    my @tags;
    foreach my $tag (@$vlan_tags){
        push(@tags,$tag->{'tag'});
    }

    return \@tags;
}

=head2 circuit_vlans_in_use

=cut
sub circuit_vlans_in_use{
    my %params = @_;
    my $db = $params{'db'};
    my $interface_id = $params{'interface_id'};

    my $circuit_tags = $db->execute_query("select circuit_edge_interface_membership.extern_vlan_id from circuit_edge_interface_membership join circuit on circuit.circuit_id = circuit_edge_interface_membership.circuit_id join circuit_instantiation on circuit.circuit_id = circuit_instantiation.circuit_id where circuit_instantiation.end_epoch = -1 and circuit_instantiation.circuit_state = 'active' and circuit.circuit_state = 'active' and circuit_edge_interface_membership.end_epoch = -1 and circuit_edge_interface_membership.interface_id = ?",[$interface_id]);

    my @tags;
    foreach my $tag (@$circuit_tags){
        push(@tags, $tag->{'extern_vlan_id'});
    }

    return \@tags;
}

=head2 create

    my ($id, $err) = OESS::DB::Interface::create(
        db    => $db,
        model => {
            admin_state             => 'known',    # Optional
            bandwidth               => 10000,      # Optional
            cloud_interconnect_id   => undef,      # Optional
            cloud_interconnect_type => undef,      # Optional
            description             => 'BACKBONE',
            mpls_vlan_tag_range     => '1-4095',   # Optional
            name                    => 'ae0',
            node_id                 => 100,
            operational_state       => 'unknown',  # Optional
            role                    => 'unknown',  # Optional
            vlan_tag_range          => '-1',       # Optional
            workgroup_id            => 100,        # Optional
            mtu                     => 9000        # Optional
        }
    );

=cut
sub create {
    my $args = {
        db    => undef,
        model => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `model` is missing.') if !defined $args->{model};
    return (undef, 'Required argument `model->description` is missing.') if !defined $args->{model}->{description};
    return (undef, 'Required argument `model->name` is missing.') if !defined $args->{model}->{name};
    return (undef, 'Required argument `model->node_id` is missing.') if !defined $args->{model}->{node_id};

    $args->{model}->{bandwidth} = (exists $args->{model}->{bandwidth}) ? $args->{model}->{bandwidth} : 10000;
    $args->{model}->{cloud_interconnect_id} = (exists $args->{model}->{cloud_interconnect_id}) ? $args->{model}->{cloud_interconnect_id} : undef;
    $args->{model}->{cloud_interconnect_type} = (exists $args->{model}->{cloud_interconnect_type}) ? $args->{model}->{cloud_interconnect_type} : undef;
    $args->{model}->{mpls_vlan_tag_range} = (exists $args->{model}->{mpls_vlan_tag_range}) ? $args->{model}->{mpls_vlan_tag_range} : '1-4095';
    $args->{model}->{admin_state} = (exists $args->{model}->{admin_state}) ? $args->{model}->{admin_state} : 'unknown';
    $args->{model}->{operational_state} = (exists $args->{model}->{operational_state}) ? $args->{model}->{operational_state} : 'unknown';
    $args->{model}->{role} = (exists $args->{model}->{role}) ? $args->{model}->{role} : 'unknown';
    $args->{model}->{vlan_tag_range} = (exists $args->{model}->{vlan_tag_range}) ? $args->{model}->{vlan_tag_range} : '-1';
    $args->{model}->{workgroup_id} = (exists $args->{model}->{workgroup_id}) ? $args->{model}->{workgroup_id} : undef;
    $args->{model}->{mtu} = (exists $args->{model}->{mtu}) ? $args->{model}->{mtu} : 9000;

    my $q1 = "INSERT into interface (name, port_number, description, cloud_interconnect_id, cloud_interconnect_type, operational_state, role, node_id, vlan_tag_range, mpls_vlan_tag_range, workgroup_id)
              VALUES (?,NULL,?,?,?,?,?,?,?,?,?)";
    my $interface_id = $args->{db}->execute_query($q1, [
        $args->{model}->{name},
        $args->{model}->{description},
        $args->{model}->{cloud_interconnect_id},
        $args->{model}->{cloud_interconnect_type},
        $args->{model}->{operational_state},
        $args->{model}->{role},
        $args->{model}->{node_id},
        $args->{model}->{vlan_tag_range},
        $args->{model}->{mpls_vlan_tag_range},
        $args->{model}->{workgroup_id}
    ]);
    if (!defined $interface_id) {
        return (undef, $args->{db}->get_error);
    }

    my $q2 = "INSERT INTO interface_instantiation (interface_id, end_epoch, start_epoch, admin_state, capacity_mbps, mtu_bytes)
              VALUES (?, -1, unix_timestamp(now()), ?, ?, ?)";
    my $ok = $args->{db}->execute_query($q2, [
        $interface_id,
        $args->{model}->{admin_state},
        $args->{model}->{bandwidth},
        $args->{model}->{mtu}
    ]);
    if (!defined $ok) {
        return (undef, $args->{db}->get_error);
    }

    return ($interface_id, undef);
}

=head2 update

    my $err = OESS::DB::Interface::update(
        db => $db,
        interface => {
            interface_id            => 1,
            cloud_interconnect_id   => 'gxcon12345',            # Optional
            cloud_interconnect_type => 'aws-hosted-vinterface', # Optional
            name                    => 'xe-7/0/0',              # Optional
            role                    => 'unknown',               # Optional
            description             => '...',                   # Optional
            operational_state       => 'up',                    # Optional
            vlan_tag_range          => '-1',                    # Optional
            mpls_vlan_tag_range     => '1-4095',                # Optional
            workgroup_id            => 1,                       # Optional
            instUpdate              => 1                        # Optional
        }
    );
    die $err if defined $err;

=cut
sub update {
    my $args = {
        db        => undef,
        interface => undef,
        @_
    };

    return 'Required argument `db` is missing.' if !defined $args->{db};
    return 'Required argument `interface` is missing.' if !defined $args->{interface};
    return 'Required argument `interface->interface_id` is missing.' if !defined $args->{interface}->{interface_id};
    my $params = [];
    my $values = [];
    if (exists $args->{interface}->{cloud_interconnect_id}) {
        push @$params, 'cloud_interconnect_id=?';
        push @$values, $args->{interface}->{cloud_interconnect_id};
    }
    if (exists $args->{interface}->{cloud_interconnect_type}) {
        push @$params, 'cloud_interconnect_type=?';
        push @$values, $args->{interface}->{cloud_interconnect_type};
    }
    if (exists $args->{interface}->{name}) {
        push @$params, 'name=?';
        push @$values, $args->{interface}->{name};
    }
    if (exists $args->{interface}->{role}) {
        push @$params, 'role=?';
        push @$values, $args->{interface}->{role};
    }
    if (exists $args->{interface}->{description}) {
        push @$params, 'description=?';
        push @$values, $args->{interface}->{description};
    }
    if (exists $args->{interface}->{operational_state}) {
        push @$params, 'operational_state=?';
        push @$values, $args->{interface}->{operational_state};
    }
    if (exists $args->{interface}->{vlan_tag_range}) {
        push @$params, 'vlan_tag_range=?';
        push @$values, $args->{interface}->{vlan_tag_range};
    }
    if (exists $args->{interface}->{mpls_vlan_tag_range}) {
        push @$params, 'mpls_vlan_tag_range=?';
        push @$values, $args->{interface}->{mpls_vlan_tag_range};
    }
    if (exists $args->{interface}->{workgroup_id}) {
        push @$params, 'workgroup_id=?';
        push @$values, $args->{interface}->{workgroup_id};
    }
    my $fields = join(', ', @$params);
    push @$values, $args->{interface}->{interface_id};
    if ($fields ne ""){
        my $ok = $args->{db}->execute_query(
            "UPDATE interface SET $fields WHERE interface_id=?",
            $values
        );
    
        if (!defined $ok) {
            return $args->{db}->get_error;
        }
    }

    my $inst_params = [];
    my $inst_values = [];

    my $curr_inst = $args->{db}->execute_query(
        "select * from interface_instantiation where end_epoch=-1 and interface_id=?",
        [$args->{interface}->{interface_id}]
    );
    if (!defined $curr_inst) {
        return $args->{db}->get_error;
    }
    if (!defined $curr_inst->[0]) {
        return "Couldn't find instantiation for interface.";
    }
    $curr_inst = $curr_inst->[0];

    my $inst_mod = 0;
    if (exists $args->{interface}->{bandwidth} && $args->{interface}->{bandwidth} != $curr_inst->{capacity_mbps}) {
        $inst_mod = 1;
        $curr_inst->{capacity_mbps} = $args->{interface}->{bandwidth};
    }
    if (exists $args->{interface}->{mtu} && $args->{interface}->{mtu} != $curr_inst->{mtu_bytes}) {
        $inst_mod = 1;
        $curr_inst->{mtu_bytes} = $args->{interface}->{mtu};
    }
    if (exists $args->{interface}->{admin_state} && $args->{interface}->{admin_state} ne $curr_inst->{admin_state}) {
        $inst_mod = 1;
        $curr_inst->{admin_state} = $args->{interface}->{admin_state};
    }

    if ($inst_mod) {
        my $inst_ok = $args->{db}->execute_query(
            "UPDATE interface_instantiation SET end_epoch=UNIX_TIMESTAMP(NOW()) WHERE interface_id=? and end_epoch = -1",
            [$args->{interface}->{interface_id}]
        );
        if (!defined $inst_ok) {
            return $args->{db}->get_error;
        }
        $inst_ok = $args->{db}->execute_query(
            "INSERT INTO interface_instantiation (capacity_mbps, mtu_bytes, admin_state, interface_id, start_epoch, end_epoch)
            VALUES (?,?,?,?, UNIX_TIMESTAMP(NOW()), -1)",
            [$curr_inst->{capacity_mbps}, $curr_inst->{mtu_bytes}, $curr_inst->{admin_state}, $args->{interface}->{interface_id}]
        );
		if (!defined $inst_ok) {
			return $args->{db}->get_error;
		}
     }

     return;
}

=head2 get_available_internal_vlan

=cut
sub get_available_internal_vlan {
    my $args = {
        db           => undef,
        interface_id => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `interface_id` is missing.') if !defined $args->{interface_id};

    my $query = "
        select CASE
        WHEN link_instantiation.interface_a_id = ?
            THEN link_path_membership.interface_a_vlan_id
            ELSE link_path_membership.interface_z_vlan_id
        END as 'internal_vlan_id'
        from link_path_membership
        join link on (
            link.link_id=link_path_membership.link_id and link_path_membership.end_epoch=-1
        )
        join link_instantiation
        on link.link_id = link_instantiation.link_id
        and link_instantiation.end_epoch=-1
        and (
            link_instantiation.interface_a_id = ? or link_instantiation.interface_z_id = ?
        )
        join path_instantiation on link_path_membership.path_id = path_instantiation.path_id
        and path_instantiation.end_epoch = -1
    ";

    my $used = {};

    my $results = $args->{db}->execute_query(
        $query,
        [$args->{interface_id}, $args->{interface_id}, $args->{interface_id}]
    );
    if (!defined $results) {
        return (undef, $args->{db}->get_error);
    }

    foreach my $row (@$results){
        $used->{$row->{'internal_vlan_id'}} = 1;
    }

    my ($allowed_vlan_tags, $err) = OESS::DB::Node::get_allowed_vlans(
        db => $args->{db},
        interface_id => $args->{interface_id}
    );
    if (defined $err) {
        return (undef, $err);
    }

    foreach my $tag (@$allowed_vlan_tags) {
        return ($tag, undef) if !exists $used->{$tag};
    }

    return (undef, "Couldn't find an available internal VLAN.");
}

1;
