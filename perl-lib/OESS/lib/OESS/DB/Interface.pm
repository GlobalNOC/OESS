#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::Interface;

use OESS::Node;

sub fetch{
    my %params = @_;
    my $db = $params{'db'};

    my $status = $params{'status'} || 'active';

    my $interface_id = $params{'interface_id'};#

    my $interface = $db->execute_query("select * from interface join interface_instantiation where interface_id = ?",[$interface_id]);

    return if (!defined($interface));

    my $acls = $db->execute_query("select * from interface_acl where interface_id = ?",[$interface_id]);
    
    my $node = OESS::Node->new( db => $db, node_id => $interface->{'node_id'});

    return {interface_id => $interface->{'interface_id'},
            role => $interface->{'role'},
            description => $interface->{'description'},
            operational_state => $interface->{'operational_state'},
            node => $node,
            vlan_tag_range => $interface->{'vlan_tag_range'},
            mpls_vlan_range => $interface->{'mpls_vlan_range'},
            workgroup_id => $interface->{'workgroup_id'},
            acls => $acls };

}

sub update{
    
}

sub _update{

}

sub _create{

}

1;
