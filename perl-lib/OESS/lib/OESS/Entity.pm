#!/usr/bin/perl

use strict;
use warnings;

package OESS::Entity;

use OESS::DB::Entity;
use Data::Dumper;

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
    $self->{'description'} = $hash->{'description'};
    $self->{'logo_url'} = $hash->{'logo_url'};
    $self->{'url'} = $hash->{'url'};
    $self->{'interfaces'} = $hash->{'interfaces'};
    $self->{'parents'} = $hash->{'parents'};
    $self->{'children'} = $hash->{'children'};
    $self->{'entity_id'} = $hash->{'entity_id'};
    warn Dumper($self->{'interfaces'});
}

sub _fetch_from_db{
    my $self = shift;

    my $info = OESS::DB::Entity::fetch(db => $self->{'db'}, entity_id => $self->{'entity_id'}, name => $self->{'name'});
    warn "ENTITY HASH: " . Dumper($info);
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
             logo_url => $self->logo_url(),
             url => $self->url(),
             description => $self->description(),
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

    push(@{$self->{'parent'}},$entity);
}

sub add_interface{
    my $self = shift;
    my $interface = shift;

    push(@{$self->{'interfaces'}},$interface);
}


1;
