#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::VRF;

use OESS::Interface;


sub fetch{
    my %params = @_;
    my $db = $params{'db'};

    my $entity_id = $params{'entity_id'};#

    my $entity = $db->execute_query("select * from entity where entity_id = ?",[$entity_id]);

    return if (!defined($entity));

    my $interfaces = $db->execute_query("select interface_id from entity_interface_membership where entity_id = ?", [$entity_id]);

    my $parents = $db->execute_query( "select entity.* from entity join entity_hierarchy on entity.entity_id = entity_hierarchy.entity_parent_id where entity_hierarchy.entity_child_id = ?",[$entity_id]);

    my $children = $db->execute_query( "select entity.* from entity join entity_hierarchy on entity.entity_id = entity_hierarchy.entity_child_id where entity_hierarchy.entity_parent_id = ?",[$entity_id]);

    my @interfaces;

    foreach my $int (@$interfaces){
        push(@interfaces,OESS::Interface->new(db => $db, interface_id => $int->{'interface_id'}));
    }

    

    return {entity_id => $entity->{'entity_id'},
            name => $entity->{'name'},
            parents => $parents,
            interfaces => \@interfaces,
            children => $children };
}


1;
