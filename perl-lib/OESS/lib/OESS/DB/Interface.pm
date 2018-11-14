#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::Interface;

use OESS::Node;
use OESS::ACL;

use Data::Dumper;

=head2 fetch

=cut
sub fetch{
    my %params = @_;
    my $db = $params{'db'};

    my $status = $params{'status'} || 'active';

    my $interface_id = $params{'interface_id'};

    my $interface = $db->execute_query("select * from interface where interface.interface_id = ?",[$interface_id]);

    return if (!defined($interface) || !defined($interface->[0]));

    $interface = $interface->[0];

    my $acls = OESS::ACL->new( db => $db, interface_id => $interface_id);
    
    my $node = OESS::Node->new( db => $db, node_id => $interface->{'node_id'});

    my $in_use = OESS::DB::Interface::vrf_vlans_in_use(db => $db, interface_id => $interface_id );

    push(@{$in_use},@{OESS::DB::Interface::circuit_vlans_in_use(db => $db, interface_id => $interface_id)});

    return {interface_id => $interface->{'interface_id'},
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
            used_vlans => $in_use };

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
=cut
sub get_interfaces{
    my %params = @_;

    my $db = $params{'db'};
   
    my @where_str;
    my @where_val;

    if(defined($params{'node_id'})){
        push(@where_val, $params{'node_id'});
        push(@where_str, "node_id = ?");
    }

    if(defined($params{'workgroup_id'})){
        push(@where_val, $params{'workgroup_id'});
        push(@where_str, "workgroup_id = ?");
    }

    
    my $where;

    foreach my $str (@where_str){
        if(!defined($where)){
            $where .= $str;
        }else{
            $where .= " and " . $str;
        }
    }

    my $query = "select interface_id from interface where $where";
    #warn "Query: " . $query . "\n";
    #warn "Query Params: " . Dumper(\@where_val);
    my $interfaces = $db->execute_query($query,\@where_val);
    my @ints;
    foreach my $int (@$interfaces){
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

1;
