#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::Entity;

use OESS::Interface;
use OESS::Entity;
use Data::Dumper;

sub fetch{
    my %params = @_;
    my $db = $params{'db'};

    my $entity_id = $params{'entity_id'};

    my $entity = $db->execute_query("select * from entity where entity_id = ?",[$entity_id]);

    return if (!defined($entity) || !defined($entity->[0]));

    $entity = $entity->[0];

    my $interfaces = $db->execute_query("select interface_id from entity_interface_membership where entity_id = ?", [$entity_id]);

    my $parents = $db->execute_query( "select entity.* from entity join entity_hierarchy on entity.entity_id = entity_hierarchy.entity_parent_id where entity_hierarchy.entity_child_id = ?",[$entity_id]);

    my $children = $db->execute_query( "select entity.* from entity join entity_hierarchy on entity.entity_id = entity_hierarchy.entity_child_id where entity_hierarchy.entity_parent_id = ?",[$entity_id]);

    my @interfaces;

    foreach my $int (@$interfaces){
        push(@interfaces,OESS::Interface->new(db => $db, interface_id => $int->{'interface_id'}));
    }

    warn Dumper($entity);
    
    return {entity_id => $entity->{'entity_id'},
            name => $entity->{'name'},
            parents => $parents,
            interfaces => \@interfaces,
            children => $children };
}

sub get_root_entities{
    my %params = @_;
    my $db = $params{'db'};
    
    warn Dumper($db);

    my $entities = $db->execute_query("select entity.entity_id from entity join entity_hierarchy on entity_hierarchy.entity_child_id = entity.entity_id where entity_hierarchy.entity_parent_id = 1",[]);
    
    my @roots;

    foreach my $entity (@$entities){
        push(@roots, OESS::Entity->new(db => $db, entity_id => $entity->{'entity_id'}));
    }
    
    return \@roots;
}

1;
