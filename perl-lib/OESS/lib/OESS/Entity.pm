#!/usr/bin/perl

use strict;
use warnings;

package OESS::Entity;

use OESS::DB::Entity;

sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.Entity");

    my %args = (
        @_
        );
    
    my $self = \%args;

    bless $self, $class;

    $self->{'logger'} = $logger;

    if(!defined($self->{'db'})){
        $self->{'logger'}->error("No Database Object specified");
        return;
    }

    my $fetch_ok = $self->_fetch_from_db();
    return undef if !$fetch_ok;
    
    return $self;    
}

sub _from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{'name'} = $hash->{'name'};
    $self->{'description'} = $hash->{'description'};
    $self->{'logo_url'} = $hash->{'logo_url'};
    $self->{'url'} = $hash->{'url'};
    $self->{'interfaces'} = $hash->{'interfaces'};
    $self->{'parents'} = $hash->{'parents'};
    $self->{'children'} = $hash->{'children'};
    $self->{'entity_id'} = $hash->{'entity_id'};
    $self->{'users'} = $hash->{'users'};
}

sub _fetch_from_db{
    my $self = shift;

    my $info = OESS::DB::Entity::fetch(db => $self->{'db'}, entity_id => $self->{'entity_id'}, name => $self->{'name'}, interface_id => $self->{'interface_id'});
    return 0 if !defined($info);

    $self->_from_hash($info);
    return 1;
}

sub update_db{
    my $self = shift;

    my $entity = $self->to_hash();

    $self->{db}->start_transaction();

    my $result = OESS::DB::Entity::remove_interfaces(db => $self->{db}, entity => $entity);
    if (!defined $result) {
        $self->{db}->rollback();
        return $self->{db}->{error};
    }

    $result = OESS::DB::Entity::add_interfaces(db => $self->{db}, entity => $entity);
    if (!defined $result) {
        $self->{db}->rollback();
        return $self->{db}->{error};
    }

    $result = OESS::DB::Entity::remove_users(db => $self->{db}, entity => $entity);
    if (!defined $result) {
        $self->{db}->rollback();
        return $self->{db}->{error};
    }

    $result = OESS::DB::Entity::add_users(db => $self->{db}, entity => $entity);
    if (!defined $result) {
        $self->{db}->rollback();
        return $self->{db}->{error};
    }

    $result = OESS::DB::Entity::remove_parents(db => $self->{db}, entity => $entity);
    if (!defined $result) {
        $self->{db}->rollback();
        return $self->{db}->{error};
    }

    $result = OESS::DB::Entity::add_parents(db => $self->{db}, entity => $entity);
    if (!defined $result) {
        $self->{db}->rollback();
        return $self->{db}->{error};
    }

    $result = OESS::DB::Entity::remove_children(db => $self->{db}, entity => $entity);
    if (!defined $result) {
        $self->{db}->rollback();
        return $self->{db}->{error};
    }

    $result = OESS::DB::Entity::add_children(db => $self->{db}, entity => $entity);
    if (!defined $result) {
        $self->{db}->rollback();
        return $self->{db}->{error};
    }

    $result = OESS::DB::Entity::update(db => $self->{'db'}, entity => $entity);
    if (!defined $result) {
        $self->{db}->rollback();
        return $self->{db}->{error};
    }

    $self->{db}->commit();
    return;
}

sub to_hash{
    my $self = shift;

    my @ints;
    foreach my $int (@{$self->interfaces()}){
        push(@ints, $int->to_hash());
    }

    my @contacts;
    foreach my $user (@{$self->users()}){
        push(@contacts, $user->to_hash());
    }

    return {
        name => $self->name(),
        logo_url => $self->logo_url(),
        url => $self->url(),
        description => $self->description(),
        interfaces => \@ints,
        parents => $self->parents(),
        contacts => \@contacts,
        children => $self->children(),
        entity_id => $self->entity_id()
    };
}

sub users {
    my $self = shift;

    return $self->{'users'} || [];
}

sub entity_id{
    my $self = shift;
    return $self->{'entity_id'};
}

sub name{
    my $self = shift;
    my $name = shift;
    if(defined($name)){
        $self->{'name'} = $name;
    }else{
        return $self->{'name'};
    }
}

sub description{
    my $self = shift;
    my $description = shift;

    if(defined($description)){
        $self->{'description'} = $description;
    }
    return $self->{'description'};
}

sub logo_url{
    my $self = shift;
    my $logo_url = shift;

    if(defined($logo_url)){
        $self->{'logo_url'} = $logo_url;
    }
    return $self->{'logo_url'};
}

sub url {
    my $self = shift;
    my $url = shift;
    if(defined($url)){
        $self->{'url'} = $url;
    }
    return $self->{'url'};
}

sub interfaces{
    my $self = shift;
    my $interfaces = shift;
    
    if(defined($interfaces)){
        $self->{'interfaces'} = $interfaces;
    }else{    
        return $self->{'interfaces'};
    }
}

sub parents{
    my $self = shift;
    my $parents = shift;
    if(defined($parents)){
        $self->{'parents'} = $parents;
    }else{
        return $self->{'parents'};
    }
}

sub children{
    my $self = shift;
    my $children = shift;

    if(defined($children)){
        $self->{'children'} = $children;
    }else{
        return $self->{'children'};
    }
}

sub add_child{
    my $self = shift;
    my $entity = shift;

    push(@{$self->{'children'}},$entity);
}

sub add_parent{
    my $self = shift;
    my $entity = shift;

    push(@{$self->{'parents'}},$entity);
}

sub add_interface {
    my $self = shift;
    my $interface = shift;

    foreach my $i (@{$self->{'interfaces'}}) {
        if ($i->{interface_id} == $interface->{interface_id}) {
            return 1;
        }
    }

    push @{$self->{'interfaces'}}, $interface;
    return 1;
}

sub remove_interface {
    my $self = shift;
    my $interface = shift;

    my @tmp = @{$self->{interfaces}};
    $self->{interfaces} = [];

    foreach my $i (@tmp) {
        if ($i->{interface_id} != $interface->{interface_id}) {
            push @{$self->{interfaces}}, $i;
        }
    }

    return 1;
}

sub add_user {
    my $self = shift;
    my $user = shift;

    foreach my $i (@{$self->{'users'}}) {
        if ($i->{user_id} == $user->{user_id}) {
            return 1;
        }
    }

    push @{$self->{'users'}}, $user;
    return 1;
}

sub remove_user {
    my $self = shift;
    my $user = shift;

    my @tmp = @{$self->{users}};
    $self->{users} = [];

    foreach my $i (@tmp) {
        if ($i->{user_id} != $user->{user_id}) {
            push @{$self->{users}}, $i;
        }
    }

    return 1;
}

1;
