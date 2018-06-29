#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::Entity;

use OESS::Interface;
use OESS::Entity;
use OESS::User;

sub fetch{
    my %params = @_;
    my $db = $params{'db'};

    my $entity_id = $params{'entity_id'};
    my $entity_name = $params{'name'};

    my $entity;
    if(defined($entity_id)){
        $entity = $db->_execute_query("select * from entity where entity_id = ?",[$entity_id]);
    }else{
        $entity = $db->_execute_query("select * from entity where name = ?",[$entity_name]);
    }

    return if (!defined($entity) || !defined($entity->[0]));

    $entity = $entity->[0];

    my $interfaces = $db->_execute_query("select interface_id from entity_interface_membership where entity_id = ?", [$entity->{'entity_id'}]);

    my $parents = $db->_execute_query( "select entity.* from entity join entity_hierarchy on entity.entity_id = entity_hierarchy.entity_parent_id where entity_hierarchy.entity_child_id = ?",[$entity->{'entity_id'}]);

    my $children = $db->_execute_query( "select entity.* from entity join entity_hierarchy on entity.entity_id = entity_hierarchy.entity_child_id where entity_hierarchy.entity_parent_id = ?",[$entity->{'entity_id'}]);

    my @interfaces;

    foreach my $int (@$interfaces){

        push(@interfaces,OESS::Interface->new(db => $db, interface_id => $int->{'interface_id'}));

    }

    my $users = $db->_execute_query( "select user_id from user_entity_membership where entity_id = ?",[$entity->{'entity_id'}]);
    
    my @users;
    foreach my $u (@$users){
        my $user = OESS::User->new( db => $db, user_id => $u->{'user_id'});
        next if !defined($user);
        push(@users,$user);
    }

    return {entity_id => $entity->{'entity_id'},
            description => $entity->{'description'},
            logo_url => $entity->{'logo_url'},
            url => $entity->{'url'},
            name => $entity->{'name'},
            parents => $parents,
            interfaces => \@interfaces,
            children => $children,
            users => \@users };
}

sub get_root_entities{
    my %params = @_;
    my $db = $params{'db'};
    
    my $entities = $db->_execute_query("select entity.entity_id from entity join entity_hierarchy on entity_hierarchy.entity_child_id = entity.entity_id where entity_hierarchy.entity_parent_id = 1",[]);
    
    my @roots;

    foreach my $entity (@$entities){
        push(@roots, OESS::Entity->new(db => $db, entity_id => $entity->{'entity_id'}));
    }
    
    return \@roots;
}

1;
