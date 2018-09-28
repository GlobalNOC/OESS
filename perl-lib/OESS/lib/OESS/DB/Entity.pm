#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::Entity;

use OESS::Interface;
use OESS::Entity;
use OESS::User;
use Data::Dumper;
use List::MoreUtils qw(uniq);

=head2 fetch

=cut
sub fetch{
    my %params = @_;
    my $db = $params{'db'};

    my $entity_id = $params{'entity_id'};
    my $entity_name = $params{'name'};
    my $interface_id = $params{'interface_id'};
    my $vlan = $params{'vlan'};

    my $entity;
    if(defined($entity_id)){
        $entity = $db->execute_query("select * from entity where entity_id = ?",[$entity_id]);
    }elsif(defined($entity_name)){
        $entity = $db->execute_query("select * from entity where name = ?",[$entity_name]);
    }elsif(defined($interface_id) && defined($vlan)){
        $entity = $db->execute_query("select * from entity where entity_id in (select entity_id from interface_acl where interface_id = ? and (vlan_start <= ? and vlan_end >= ?))",[$interface_id,$vlan,$vlan]);
    }else{
        return;
    }

    return if (!defined($entity) || !defined($entity->[0]));

    $entity = $entity->[0];

    my $interfaces = $db->execute_query("select interface_id from interface_acl where entity_id = ?",[$entity->{'entity_id'}]);

    my $parents = $db->execute_query( "select entity.* from entity join entity_hierarchy on entity.entity_id = entity_hierarchy.entity_parent_id where entity_hierarchy.entity_child_id = ?",[$entity->{'entity_id'}]);

    my $children = $db->execute_query( "select entity.* from entity join entity_hierarchy on entity.entity_id = entity_hierarchy.entity_child_id where entity_hierarchy.entity_parent_id = ?",[$entity->{'entity_id'}]);

    my @interfaces;

    foreach my $int (@$interfaces){
        push(@interfaces,OESS::Interface->new(db => $db, interface_id => $int->{'interface_id'}));

    }

    my $users = $db->execute_query( "select user_id from user_entity_membership where entity_id = ?",[$entity->{'entity_id'}]);
    
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

=head2 get_root_entities

=cut
sub get_root_entities{
    my %params = @_;
    my $db = $params{'db'};
    
    my $entities = $db->execute_query("select entity.entity_id from entity join entity_hierarchy on entity_hierarchy.entity_child_id = entity.entity_id where entity_hierarchy.entity_parent_id = 1",[]);
    
    my @roots;

    foreach my $entity (@$entities){
        push(@roots, OESS::Entity->new(db => $db, entity_id => $entity->{'entity_id'}));
    }
    
    return \@roots;
}

=head2 get_entities

=cut
sub get_entities {
    my %params = @_;
    my $db = $params{'db'};
    my $name = $params{'name'};

    my $reqs = [];
    my $args = [];

    my $where = 'where entity_hierarchy.entity_parent_id != 1';
    if (defined $name) {
        $where .= " and entity.name like ?";
        push @$args, "%$name%";
    }
    warn "$where";

    my $entities = $db->execute_query(
        "select entity.entity_id, entity.name from entity
        join entity_hierarchy on entity_hierarchy.entity_child_id=entity.entity_id
        $where
        group by entity.entity_id
        order by entity.name",
        $args
    );

    my $result = [];
    foreach my $entity (@$entities){
        push @$result, OESS::Entity->new(db => $db, entity_id => $entity->{'entity_id'});
    }
    return $result;
}

=head2 update

=cut
sub update {
    my %params = @_;
    my $db = $params{'db'};
    my $entity = $params{'entity'};

    return if (!defined $entity->{entity_id});

    my $reqs = [];
    my $args = [];
    my $set = '';

    if (defined $entity->{description}) {
        push @$reqs, 'description=?';
        push @$args, $entity->{description};
    }
    if (defined $entity->{logo_url}) {
        push @$reqs, 'logo_url=?';
        push @$args, $entity->{logo_url};
    }
    if (defined $entity->{name}) {
        push @$reqs, 'name=?';
        push @$args, $entity->{name};
    }
    if (defined $entity->{url}) {
        push @$reqs, 'url=?';
        push @$args, $entity->{url};
    }
    $set .= join(', ', @$reqs);
    push @$args, $entity->{entity_id};

    my $result = $db->execute_query(
        "UPDATE entity SET $set WHERE entity_id=?",
        $args
    );

    return $result;
}

=head2 remove_interfaces

=cut
sub remove_interfaces {
    my %params = @_;
    my $db = $params{'db'};
    my $entity = $params{'entity'};

    my $result = $db->execute_query(
        "DELETE from entity_interface_membership where entity_id=?",
        [$entity->{entity_id}]
    );

    return $result;
}

=head2 add_interfaces

=cut
sub add_interfaces {
    my %params = @_;
    my $db = $params{'db'};
    my $entity = $params{'entity'};

    if (@{$entity->{interfaces}} == 0) {
        return 1;
    }

    my @interface_ids = uniq map {$_->{interface_id}} @{$entity->{interfaces}};

    my $values = [];
    my $params = [];
    foreach my $intf_id (@interface_ids) {
        push @$params, '(?, ?)';

        push @$values, $entity->{entity_id};
        push @$values, $intf_id;
    }

    my $param_str = join(', ', @$params);

    return $db->execute_query(
        "INSERT into entity_interface_membership (entity_id, interface_id) VALUES $param_str",
        $values
    );
}

=head2 remove_users

=cut
sub remove_users {
    my %params = @_;
    my $db = $params{'db'};
    my $entity = $params{'entity'};

    my $result = $db->execute_query(
        "DELETE from user_entity_membership where entity_id=?",
        [$entity->{entity_id}]
    );

    return $result;
}

=head2 add_users

=cut
sub add_users {
    my %params = @_;
    my $db = $params{'db'};
    my $entity = $params{'entity'};

    if (@{$entity->{contacts}} == 0) {
        return 1;
    }

    my @user_ids = uniq map {$_->{user_id}} @{$entity->{contacts}};

    my $values = [];
    my $params = [];
    foreach my $user_id (@user_ids) {
        push @$params, '(?, ?)';

        push @$values, $entity->{entity_id};
        push @$values, $user_id;
    }

    my $param_str = join(', ', @$params);

    return $db->execute_query(
        "INSERT into user_entity_membership (entity_id, user_id) VALUES $param_str",
        $values
    );
}

=head2 remove_parents

=cut
sub remove_parents {
    my %params = @_;
    my $db = $params{'db'};
    my $entity = $params{'entity'};

    my $result = $db->execute_query(
        "DELETE from entity_hierarchy where entity_child_id=?",
        [$entity->{entity_id}]
    );

    return $result;
}

=head2 add_parents

=cut
sub add_parents {
    my %params = @_;
    my $db = $params{'db'};
    my $entity = $params{'entity'};

    if (@{$entity->{parents}} == 0) {
        return 1;
    }

    my @parent_ids = uniq map {$_->{entity_id}} @{$entity->{parents}};

    my $params = [];
    my $values = [];
    foreach my $parent (@parent_ids) {
        # The next line prevents an entity from being its own parent.
        next if $parent == $entity->{entity_id};

        push @$params, '(?, ?)';

        push @$values, $parent;              # entity_parent_id
        push @$values, $entity->{entity_id}; # entity_child_id
    }

    my $param_str = join(', ', @$params);

    return $db->execute_query(
        "INSERT into entity_hierarchy (entity_parent_id, entity_child_id) VALUES $param_str",
        $values
    );
}

=head2 remove_children

=cut
sub remove_children {
    my %params = @_;
    my $db = $params{'db'};
    my $entity = $params{'entity'};

    my $result = $db->execute_query(
        "DELETE from entity_hierarchy where entity_parent_id=?",
        [$entity->{entity_id}]
    );

    return $result;
}

=head2 add_children

=cut
sub add_children {
    my %params = @_;
    my $db = $params{'db'};
    my $entity = $params{'entity'};

    if (@{$entity->{children}} == 0) {
        return 1;
    }

    my @child_ids = uniq map {$_->{entity_id}} @{$entity->{children}};

    my $params = [];
    my $values = [];
    foreach my $child (@child_ids) {
        # The next line prevents an entity from being its own child.
        next if $child == $entity->{entity_id};

        push @$params, '(?, ?)';

        push @$values, $entity->{entity_id}; # entity_parent_id
        push @$values, $child;               # entity_child_id
    }

    my $param_str = join(', ', @$params);

    return $db->execute_query(
        "INSERT into entity_hierarchy (entity_parent_id, entity_child_id) VALUES $param_str",
        $values
    );
}

1;
