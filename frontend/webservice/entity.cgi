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
        required        => 1,
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
        required        => 1,
        description     => "The Entity ID to find the interfaces for"   );

    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name => 'get_entity',
        description => 'get the details on an entity',
        callback => sub { get_entity(@_)});

    $method->add_input_parameter(
        name            => 'entity_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "The Entity ID to find the interfaces for"   );

    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "The workgroup id to find the ACLs for the entity"   );
    
    $svc->register_method($method);
}

sub register_rw_methods{
    
    my $method = GRNOC::WebService::Method->new(
        name            => "update_entity",
        description     => "",
        callback        => sub { update_entity(@_) }
        );
    
    $method->add_input_parameter(
        name => 'entity_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
        description => "entity to be updated");

    $method->add_input_parameter(
        name => 'description',
        pattern => $GRNOC::WebService::Regex::TEXT,
        required => 0,
        description => "the description to be set on the entity");

    $method->add_input_parameter(
        name => 'name',
        pattern => $GRNOC::WebService::Regex::NAME,
        required => 0,
        description => "the name of the entity");

    $method->add_input_parameter(
        name => 'url',
        pattern => $GRNOC::WebService::Regex::URL,
        required => 0,
        description => "The URL of the entities web page");

    $method->add_input_parameter(
        name => 'logo_url',
        pattern => $GRNOC::WebService::Regex::TEXT,
        required => 0,
        description => "The URL to the logo for the entity");

    $svc->register_method($method);
    
}

sub update_entity{
    my $method = shift;
    my $params = shift;
    my $ref = shift;

    my $entity = OESS::Entity->new(db => $db, entity_id => $params->{entity_id}{value});
    if (!defined $entity) {
        $method->set_error("Unable to find entity: " . $params->{'entity_id'}{'value'} . " in the Database");
    }

    if (defined $params->{description}{value}) {
        $entity->description($params->{description}{value});
    }
    if (defined $params->{logo_url}{value}) {
        $entity->logo_url($params->{logo_url}{value});
    }
    if (defined $params->{name}{value}) {
        $entity->name($params->{name}{value});
    }
    if (defined $params->{url}{value}) {
        $entity->url($params->{url}{value});
    }

    my $result = $entity->_update_db();
    return { results => [ { success => 1 } ] };
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

    return {results => \@entities};
}

sub get_entity_children{
    my $method = shift;
    my $params = shift;
    my $ref = shift;

    my $entity = OESS::Entity->new(db => $db, entity_id => $params->{'entity_id'}{'value'});

    if(!defined($entity)){
        $method->set_error("Unable to find entity: " . $params->{'entity_id'}{'value'} . " in the Database");
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

sub get_entity{
    my $method = shift;
    my $params = shift;
    my $ref =  shift;

    my $workgroup_id = $params->{'workgroup_id'}{'value'};
    my $entity = OESS::Entity->new(db => $db, entity_id => $params->{'entity_id'}{'value'});

    if(!defined($entity)){
        return;
    }

    my %vlans;

    my @ints;
    foreach my $int (@{$entity->interfaces()}){
        my $obj = $int->to_hash();
        my @allowed_vlans;
        for(my $i=1;$i<=4095;$i++){
            if($int->vlan_valid( workgroup_id => $workgroup_id, vlan => $i )){
                push(@allowed_vlans,$i);
                $vlans{$i} = 1;
            }
        }
        $obj->{'available_vlans'} = \@allowed_vlans;
        push(@ints,$obj);
    }
    
    my $res = $entity->to_hash();
    $res->{'interfaces'} = \@ints;
    $res->{'allowed_vlans'} = keys %vlans;
    return {results => $res};
    
}



sub main{
    register_ro_methods();
    register_rw_methods();
    
    $svc->handle_request();
}

main();
