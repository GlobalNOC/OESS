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

    $self->_fetch_from_db();
    
    return $self;    
}

sub _from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{'name'} = $hash->{'name'};
    $self->{'interfaces'} = $hash->{'interfaces'};
    $self->{'parents'} = $hash->{'parents'};
    $self->{'children'} = $hash->{'children'};
    $self->{'entity_id'} = $hash->{'entity_id'};
}

sub _fetch_from_db{
    my $self = shift;

    my $info = OESS::DB::Entity::fetch(db => $self->{'db'}, entity_id => $self->{'entity_id'});
    $self->_from_hash($info);
}

sub _update_db{
    my $self = shift;
    return OESS::DB::Entity->update(db => $self->{'db'}, entity => $self->to_hash());
}

sub to_hash{
    my $self = shift;

    my @ints;

    foreach my $int (@{$self->interfaces()}){
        push(@ints, $int->to_hash());
    }

    return { name => $self->name(),
             interfaces => \@ints,
             parents => $self->parents(),
             children => $self->children(),
             entity_id => $self->entity_id() };

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

    push(@{$self->{'parent'}},$entity);
}

sub add_interface{
    my $self = shift;
    my $interface = shift;

    push(@{$self->{'interfaces'}},$interface);
}


1;
