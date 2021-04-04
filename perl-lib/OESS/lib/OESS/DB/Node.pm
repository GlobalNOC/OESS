use strict;
use warnings;

package OESS::DB::Node;

use Data::Dumper;
use Socket qw( inet_aton inet_ntoa);

use constant MAX_VLAN_TAG => 4096;
use constant MIN_VLAN_TAG => 1;
use constant UNTAGGED => -1;

=head2 fetch

=cut
sub fetch{
    my %params = @_;
    my $db = $params{'db'};

    my $status = $params{'status'} || 'active';

    my $node_id = $params{'node_id'};
    my $node_name = $params{'name'};
    my $details;

    my $node;

    if (defined $node_id) {
        $node = $db->execute_query("select * from node join node_instantiation on node.node_id=node_instantiation.node_id where node.node_id=? and node_instantiation.end_epoch=-1", [ $node_id ]);
    } else {
        $node = $db->execute_query("select * from node join node_instantiation on node.node_id=node_instantiation.node_id where node.name=? and node_instantiation.end_epoch=-1", [ $node_name ]);
    }

    return if (!defined $node || !defined $node->[0]);
    return $node->[0];
}

=head2 get_node_interfaces

=cut
sub get_node_interfaces{
    my $db = shift;
    my $node_id = shift;

    my $interfaces = $db->execute_query("select * from interface where node_id = ?",[$node_id]);

    my @ints;
    foreach my $interface (@$interfaces){
        push(@ints, OESS::Interface->new(db => $db, interface_id => $interface->{'interface_id'}));
    }

    return \@ints;
}

=head2 get_allowed_vlans

=cut
sub get_allowed_vlans {
    my $args = {
        db           => undef,
        node_id      => undef,
        interface_id => undef,
        @_
    };

    my $params = [];
    my $values = [];

    if (defined $args->{node_id}) {
        push @$params, "node.node_id=?";
        push @$values, $args->{node_id};
    }
    if (defined $args->{interface_id}) {
        push @$params, "interface.interface_id=?";
        push @$values, $args->{interface_id};
    }

    my $where = (@$params > 0) ? 'where ' . join(' and ', @$params) : '';

    my $q = "
        SELECT node.vlan_tag_range
        FROM node
        JOIN interface ON node.node_id=interface.node_id
        $where
        GROUP BY node.node_id
    ";

    my $results = $args->{db}->execute_query($q, $values);
    if (!defined $results) {
        return (undef, $args->{db}->get_error);
    }

    my $string = $results->[0]->{vlan_tag_range};
    my $tags = _process_tag_string($string);

    return $tags;
}

=head2 _process_tag_string

=cut
sub _process_tag_string{
    my $string        = shift;
    my $oscars_format = shift || 0;
    my $MIN_VLAN_TAG  = ($oscars_format) ? 0 : MIN_VLAN_TAG;

    if(!defined($string)){
        return;
    }
    if($oscars_format){
        $string =~ s/^-1/0/g;
        $string =~ s/,-1/0/g;
    }

    if ($string eq '-1') {
        return []
    }

    my @split = split(/,/, $string);
    my @tags;

    foreach my $element (@split){
        if ($element =~ /^(\d+)-(\d+)$/){

            my $start = $1;
            my $end   = $2;

            if (($start < MIN_VLAN_TAG && $start != UNTAGGED)|| $end > MAX_VLAN_TAG){
                return;
            }

            foreach my $tag_number ($start .. $end){
                push(@tags, $tag_number);
            }

        }elsif ($element =~ /^(\-?\d+)$/){
            my $tag_number = $1;
            if (($tag_number < MIN_VLAN_TAG && $tag_number != UNTAGGED) || $tag_number > MAX_VLAN_TAG){
                return;
            }
            push (@tags, $1);

        }else{
            return;
        }
    }

    return \@tags;
}

=head2 create

    my ($id, $err) = OESS::DB::Node::create(
        db    => $db,
        model => {
            controller       => 'netconf'      # 'netconf', 'nso', or 'openflow'
            ip_address       => '192.168.1.1',
            latitude         => 1.01,
            longitude        => 1.01,
            loopback_address => '127.0.0.1'    # Optional. Default provided.
            make             => 'Juniper',
            model            => 'MX',
            name             => 'demo-switch.example.com'
            short_name       => 'demo-switch', # Optional. Defaults to `name`.
            sw_version       => undef,         # Optional. Default provided.
            tcp_port         => 830,           # Optional. Default provided.
            vlan_range       => '1-4095'       # Optional. Default provided.
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
    return (undef, 'Required argument `model->name` is missing.') if !defined $args->{model}->{name};
    return (undef, 'Required argument `model->latitude` is missing.') if !defined $args->{model}->{latitude};
    return (undef, 'Required argument `model->longitude` is missing.') if !defined $args->{model}->{longitude};
    return (undef, 'Required argument `model->ip_address` is missing.') if !defined $args->{model}->{ip_address};
    return (undef, 'Required argument `model->make` is missing.') if !defined $args->{model}->{make};
    return (undef, 'Required argument `model->model` is missing.') if !defined $args->{model}->{model};
    return (undef, 'Required argument `model->controller` is missing.') if !defined $args->{model}->{controller};

    if (!defined $args->{model}->{dpid}) {
        my $data = inet_aton($args->{model}->{ip_address});
        $args->{model}->{dpid} = unpack('N', $data);
    }

    my $valid_controllers = {openflow =>1, netconf => 1, nso => 1};
    if (!defined $valid_controllers->{$args->{model}->{controller}}) {
        return (undef, "Invalid controller '$args->{model}->{controller}' provided.");
    }

    my $q = "
    INSERT INTO node (
        network_id, name, short_name, latitude, longitude, vlan_tag_range
    ) VALUES (?, ?, ?, ?, ?, ?)
    ";
    my $node_id = $args->{db}->execute_query($q, [
        1,
        $args->{model}->{name},
        $args->{model}->{short_name} || $args->{model}->{name},
        $args->{model}->{latitude},
        $args->{model}->{longitude},
        $args->{model}->{vlan_range} || '1-4095'
    ]);
    if (!defined $node_id) {
        return (undef, $args->{db}->get_error);
    }

    my $q2 = "
    insert into node_instantiation (
        node_id, start_epoch, end_epoch, admin_state,
        dpid, mgmt_addr, loopback_address, tcp_port,
        vendor, model, sw_version,
        mpls, openflow, controller
    ) VALUES (?,UNIX_TIMESTAMP(NOW()),-1,?,?,?,?,?,?,?,?,?,?,?)
    ";
    my $ok = $args->{db}->execute_query($q2, [
        $node_id,
        'active',
        $args->{model}->{dpid},
        $args->{model}->{ip_address},
        $args->{model}->{loopback_address} || '127.0.0.1',
        $args->{model}->{tcp_port} || 830,
        $args->{model}->{make},
        $args->{model}->{model},
        $args->{model}->{sw_version},
        1,
        0,
        $args->{model}->{controller}
    ]);
    if (!defined $ok) {
        return (undef, $args->{db}->get_error);
    }
    return ($node_id, undef);
}

=head2 update

=cut
sub update {
    my $args = {
        db   => undef,
        node => {},
        @_
    };

    return 'Required argument `db` is missing.' if !defined $args->{db};
    return 'Required argument `node` is missing.' if !defined $args->{node};
    return 'Required argument `node->node_id` is missing.' if !defined $args->{node}->{node_id};

    my $params = [];
    my $values = [];

    if (exists $args->{node}->{name}) {
        push @$params, 'name=?';
        push @$values, $args->{node}->{name};
    }
    if (exists $args->{node}->{short_name}) {
        push @$params, 'short_name=?';
        push @$values, $args->{node}->{short_name};
    }
    if (exists $args->{node}->{latitude}) {
        push @$params, 'latitude=?';
        push @$values, $args->{node}->{latitude};
    }
    if (exists $args->{node}->{longitude}) {
        push @$params, 'longitude=?';
        push @$values, $args->{node}->{longitude};
    }
    if (exists $args->{node}->{operational_state_mpls}) {
        push @$params, 'operational_state_mpls=?';
        push @$values, $args->{node}->{operational_state_mpls};
    }
    if (exists $args->{node}->{vlan_range}) {
        push @$params, 'vlan_tag_range=?';
        push @$values, $args->{node}->{vlan_range};
    }
    if (exists $args->{node}->{pending_diff}) {
        push @$params, 'pending_diff=?';
        push @$values, $args->{node}->{pending_diff};
    }

    my $fields = join(', ', @$params);
    push @$values, $args->{node}->{node_id};

    if ($fields ne "") {
        my $ok = $args->{db}->execute_query(
            "UPDATE node SET $fields WHERE node_id=?",
            $values
        );
        return $args->{db}->get_error if !defined $ok;
    }

    $params = [];
    $values = [];

    my $res = $args->{db}->execute_query("
        SELECT
        node_id, admin_state, dpid, openflow, mpls,
        vendor as make, model, sw_version,
        mgmt_addr as ip_address, loopback_address,
        tcp_port, controller
        FROM node_instantiation where end_epoch=-1 and node_id=?",
        [$args->{node}->{node_id}]
    );
    if (!defined $res) {
        return $args->{db}->get_error;
    }
    if (!defined $res->[0]) {
        return "Couldn't find instantiation for node.";
    }
    my $inst = $res->[0];
    my $inst_mod = 0;

    if (exists $args->{node}->{ip_address} && $args->{node}->{ip_address} ne $inst->{ip_address}) {
        $inst_mod = 1;
        $inst->{ip_address} = $args->{node}->{ip_address};
    }
    if (exists $args->{node}->{loopback_address} && $args->{node}->{loopback_address} ne $inst->{loopback_address}) {
        $inst_mod = 1;
        $inst->{loopback_address} = $args->{node}->{loopback_address};
    }
    if (exists $args->{node}->{tcp_port} && $args->{node}->{tcp_port} != $inst->{tcp_port}) {
        $inst_mod = 1;
        $inst->{tcp_port} = $args->{node}->{tcp_port};
    }
    if (exists $args->{node}->{make} && $args->{node}->{make} ne $inst->{make}) {
        $inst_mod = 1;
        $inst->{make} = $args->{node}->{make};
    }
    if (exists $args->{node}->{model} && $args->{node}->{model} ne $inst->{model}) {
        $inst_mod = 1;
        $inst->{model} = $args->{node}->{model};
    }
    if (exists $args->{node}->{sw_version} && $args->{node}->{sw_version} ne $inst->{sw_version}) {
        $inst_mod = 1;
        $inst->{sw_version} = $args->{node}->{sw_version};
    }
    if (exists $args->{node}->{controller} && $args->{node}->{controller} ne $inst->{controller}) {
        $inst_mod = 1;
        $inst->{controller} = $args->{node}->{controller};
    }
    if (exists $args->{node}->{dpid} && $args->{node}->{dpid} ne $inst->{dpid}) {
        $inst_mod = 1;
        $inst->{dpid} = $args->{node}->{dpid};
    }
    if (exists $args->{node}->{admin_state} && $args->{node}->{admin_state} ne $inst->{admin_state}) {
        $inst_mod = 1;
        $inst->{admin_state} = $args->{node}->{admin_state};
    }

    if ($inst_mod) {
        my $inst_ok = $args->{db}->execute_query(
            "UPDATE node_instantiation SET end_epoch=UNIX_TIMESTAMP(NOW()) WHERE node_id=? and end_epoch=-1",
            [$args->{node}->{node_id}]
        );
        if (!defined $inst_ok) {
            return $args->{db}->get_error;
        }
        $inst_ok = $args->{db}->execute_query(
            "INSERT INTO node_instantiation (
                mgmt_addr, loopback_address, tcp_port, dpid,
                vendor, model, sw_version, controller,
                admin_state, openflow, mpls,
                node_id, start_epoch, end_epoch
            )
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,UNIX_TIMESTAMP(NOW()),-1)",
            [
                $inst->{ip_address},
                $inst->{loopback_address},
                $inst->{tcp_port},
                $inst->{dpid},
                $inst->{make},
                $inst->{model},
                $inst->{sw_version},
                $inst->{controller},
                $inst->{admin_state},
                $inst->{openflow},
                $inst->{mpls},
                $args->{node}->{node_id}
            ]
        );
		if (!defined $inst_ok) {
			return $args->{db}->get_error;
		}
    }

    return;
}

=head2 decom

    my $err = OESS::DB::Node::decom(
        db      => $db,
        node_id => 1234
    );

=cut
sub decom {
    my $args = {
        db      => undef,
        node_id => undef,
        @_
    };

    return 'Required argument `db` is missing.' if !defined $args->{db};
    return 'Required argument `node_id` is missing.' if !defined $args->{node_id};

    my $res = $args->{db}->execute_query("
        SELECT * FROM node_instantiation where end_epoch=-1 and node_id=?",
        [$args->{node_id}]
    );
    if (!defined $res) {
        return $args->{db}->get_error;
    }
    if (!defined $res->[0]) {
        return "Couldn't find instantiation for node.";
    }
    my $inst = $res->[0];

    my $inst_ok = $args->{db}->execute_query(
        "UPDATE node_instantiation SET end_epoch=UNIX_TIMESTAMP(NOW()) WHERE node_id=? and end_epoch=-1",
        [$args->{node_id}]
    );
    if (!defined $inst_ok) {
        return $args->{db}->get_error;
    }
    $inst_ok = $args->{db}->execute_query(
        "INSERT INTO node_instantiation (
            mgmt_addr, loopback_address, tcp_port, dpid,
            vendor, model, sw_version, controller,
            admin_state, openflow, mpls,
            node_id, start_epoch, end_epoch
        )
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,UNIX_TIMESTAMP(NOW()),-1)",
        [
            $inst->{mgmt_addr},
            $inst->{loopback_address},
            $inst->{tcp_port},
            $inst->{dpid},
            $inst->{vendor},
            $inst->{model},
            $inst->{sw_version},
            $inst->{controller},
            'decom',
            $inst->{openflow},
            $inst->{mpls},
            $args->{node_id}
        ]
    );
    if (!defined $inst_ok) {
        return $args->{db}->get_error;
    }

    return;
}

1;
