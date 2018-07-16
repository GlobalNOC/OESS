#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::Interface;

use OESS::Node;
use OESS::ACL;

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

    push(@{$in_use},OESS::DB::Interface::circuit_vlans_in_use(db => $db, interface_id => $interface_id));

    return {interface_id => $interface->{'interface_id'},
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

sub get_interface{
    my %params = @_;
    
    my $db = $params{'db'};
    my $interface_name= $params{'interface'};
    my $node_name = $params{'node'};
    
    my $interface = $db->_execute_query("select interface_id from interface where name=? and node_id=(select node_id from node where name=?)",[$interface_name, $node_name]);

    if(!defined($interface) || !defined($interface->[0])){
        return;
    }

    return $interface->[0]->{'interface_id'};
}

sub get_acls{
    my %params = @_;

    my $db = $params{'db'};
    my $interface_id = $params{'interface_id'};

    my $acls = $db->execute_query("select * from interface_acl where interface_id = ?",[$interface_id]);
    return $acls;
}

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

sub circuit_vlans_in_use{
    my %params = @_;
    my $db = $params{'db'};
    my $interface_id = $params{'interface_id'};

    
}

sub update{
    
}

sub _update{

}

sub _create{

}

1;
