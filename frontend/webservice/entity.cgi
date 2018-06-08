#!/usr/bin/perl -I /home/aragusa/OESS/perl-lib/OESS/lib

use strict;
use warnings;

use GRNOC::WebService::Dispatcher;
use GRNOC::WebService::Method;

use OESS::DB;
use OESS::Entity;

#register web service dispatcher
my $svc    = GRNOC::WebService::Dispatcher->new(method_selector => ['method', 'action']);
my $db = OESS::DB->new();
my $username = $ENV{'REMOTE_USER'};
#my $is_admin = $db->get_user_admin_status( 'username' => $username );


sub register_ro_methods{


    my $method = GRNOC::WebService::Method->new(
        name            => "get_root_entities",
        description     => "returns a JSON object representing the root entities",
        callback        => sub { get_root_entities() }
        );

    $svc->register_method($method);


    $method = GRNOC::WebService::Method->new(
        name => 'get_entity_children',
        description => "returns the entities children",
        callback => sub { get_entity_children(@_) }
        );

    # add the required input parameter workgroup_id
    $method->add_input_parameter(
        name            => 'entity_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "The Entity ID to find the children entities"   );
                                             
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name => 'get_entity_interfaces',
        description => "returns the interfaces associated to the current entity (not children)",
        callback => sub { get_entity_interfaces(@_) }
        );

    # add the required input parameter workgroup_id
    $method->add_input_parameter(
        name            => 'entity_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "The Entity ID to find the interfaces for"   );

    $svc->register_method($method);

}

sub register_rw_methods{

}


sub get_root_entities{
    my $method = shift;
    my $params = shift;
    my $ref = shift;

    my $root_entities = OESS::DB::Entity::get_root_entities(db => $db);
    
    my @entities;
    foreach my $ent (@$root_entities){
        push(@entities,$ent->to_hash());
    }

    warn Dumper(\@entities);

    return {results => \@entities};
}

sub get_entity_children{
    my $method = shift;
    my $params = shift;
    my $ref = shift;

    my $entity = OESS::Entity->new(db => $db, entity_id => $params->{'entity_id'}{'value'});

    if(!defined($entity)){
        return;
    }

    my @children;
    foreach my $ent (@{$entity->children()}){
        push(@children, OESS::Entity->new(db => $db, entity_id => $ent->{'entity_id'})->to_hash());
    }

    return {results => \@children};
}

sub get_entity_interfaces{
    my $method = shift;
    my $params = shift;
    my $ref    = shift;

    my $entity = OESS::Entity->new(db => $db, entity_id => $params->{'entity_id'}{'value'});

    if(!defined($entity)){
        return;
    }

    my @res;
    foreach my $int (@{$entity->interfaces()}){
        push(@res,$int->to_hash());
    }
    
    return {results => \@res};

}



sub main{
    register_ro_methods();
    register_rw_methods();
    
    $svc->handle_request();
}

main();
