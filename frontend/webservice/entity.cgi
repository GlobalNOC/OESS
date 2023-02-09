#!/usr/bin/perl

use strict;
use warnings;

use GRNOC::WebService::Dispatcher;
use GRNOC::WebService::Method;
use List::MoreUtils qw(any uniq);
use OESS::DB;
use OESS::DB::User;
use OESS::Entity;
use OESS::VRF;


my $svc = GRNOC::WebService::Dispatcher->new(method_selector => ['method', 'action']);
my $db = OESS::DB->new();
my $username = $ENV{'REMOTE_USER'};


sub register_ro_methods{


    my $method = GRNOC::WebService::Method->new(
        name            => "get_root_entities",
        description     => "returns a JSON object representing the root entities",
        callback        => sub { get_root_entities() }
        );

    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name            => "get_entities",
        description     => "returns a JSON object representing all entities",
        callback        => sub { get_entities(@_) }
    );
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The workgroup id to find the ACLs for the entity"
    );
    $method->add_input_parameter(
        name            => 'name',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 0,
        description     => "Name of entity to search for."
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
    
    $method->add_input_parameter(
        name            => 'vrf_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "The workgroup id to find the ACLs for the entity"   );

    $method->add_input_parameter(
        name            => 'circuit_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "The workgroup id to find the ACLs for the entity"   );

    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name            => "get_valid_users",
        description     => "returns a JSON object representing all valid user for given entity",
        callback        => sub { get_valid_users(@_) }
    );
    $method->add_input_parameter(
        name            => 'entity_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The entity id to find the users the entity"
    );
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
        pattern => $GRNOC::WebService::Regex::NAME_ID,
        required => 0,
        description => "the name of the entity");
    $method->add_input_parameter(
        name => 'url',
        pattern => $GRNOC::WebService::Regex::TEXT,
        required => 0,
        description => "The URL of the entities web page");
    $method->add_input_parameter(
        name => 'logo_url',
        pattern => $GRNOC::WebService::Regex::TEXT,
        required => 0,
        description => "The URL to the logo for the entity");
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name            => "add_interface",
        description     => "",
        callback        => sub { add_interface(@_) }
    );
    $method->add_input_parameter(
        name => 'entity_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
        description => "entity to be updated"
    );
    $method->add_input_parameter(
        name => 'interface_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
        description => "interface to be added"
    );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name            => "remove_interface",
        description     => "",
        callback        => sub { remove_interface(@_) }
    );
    $method->add_input_parameter(
        name => 'entity_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
        description => "entity to be updated"
    );
    $method->add_input_parameter(
        name => 'interface_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
        description => "interface to be removed"
    );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name            => "add_user",
        description     => "",
        callback        => sub { add_user(@_) }
    );
    $method->add_input_parameter(
        name => 'entity_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
        description => "entity to be updated"
    );
    $method->add_input_parameter(
        name => 'user_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
        description => "user to be added"
    );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name            => "remove_user",
        description     => "",
        callback        => sub { remove_user(@_) }
    );
    $method->add_input_parameter(
        name => 'entity_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
        description => "entity to be updated"
    );
    $method->add_input_parameter(
        name => 'user_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
        description => "user to be removed"
    );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name            => "add_child_entity",
        description     => "Adding child entity",
        callback        => sub { add_child_entity(@_) }
    );

    $method->add_input_parameter(
        name => "current_entity_id",
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
	description => "entity to be updated"
    );
    $method->add_input_parameter(
        name => 'user_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
        description => "user to be added"
    );
    $method->add_input_parameter(
        name => 'description',
        pattern => $GRNOC::WebService::Regex::TEXT,
        required => 0,
        description => "the description to be set on the entity");
    $method->add_input_parameter(
        name => 'name',
        pattern => $GRNOC::WebService::Regex::NAME_ID,
        required => 0,
        description => "the name of the entity");
    $method->add_input_parameter(
        name => 'url',
        pattern => $GRNOC::WebService::Regex::TEXT,
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
        $method->set_error("Unable to find entity: " . $params->{'entity_id'}{'value'} . " in the Database.");
        return;
    }

    if (!_may_modify_entity($username, $entity)) {
        $method->set_error('Entity may not be modified by current user.');
        return;
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

    my $result = $entity->update_db();
    return { results => [ { success => 1 } ] };
}

sub add_interface {
    my $method = shift;
    my $params = shift;
    my $ref = shift;

    my $entity = OESS::Entity->new(db => $db, entity_id => $params->{entity_id}{value});
    if (!defined $entity) {
        $method->set_error("Unable to find entity $params->{'entity_id'}{'value'} in the db.");
        return;
    }

    if (!_may_modify_entity($username, $entity)) {
        $method->set_error('Entity may not be modified by current user.');
        return;
    }

    my $interface = OESS::Interface->new(db => $db, interface_id => $params->{interface_id}{value});
    if (!defined $interface) {
        $method->set_error("Unable to find interface $params->{'interface_id'}{'value'} in the db.");
        return;
    }

    $entity->add_interface($interface);
    my $err = $entity->update_db();
    if (defined $err) {
        $method->set_error("$err");
        return;
    }

    return { results => [ { success => 1 } ] };
}

sub remove_interface {
    my $method = shift;
    my $params = shift;
    my $ref = shift;

    my $entity = OESS::Entity->new(db => $db, entity_id => $params->{entity_id}{value});
    if (!defined $entity) {
        $method->set_error("Unable to find entity $params->{'entity_id'}{'value'} in the db.");
        return;
    }

    if (!_may_modify_entity($username, $entity)) {
        $method->set_error('Entity may not be modified by current user.');
        return;
    }

    my $interface = OESS::Interface->new(db => $db, interface_id => $params->{interface_id}{value});
    if (!defined $interface) {
        $method->set_error("Unable to find interface $params->{'interface_id'}{'value'} in the db.");
        return;
    }

    $entity->remove_interface($interface);
    my $err = $entity->update_db();
    if (defined $err) {
        $method->set_error("$err");
        return;
    }

    return { results => [ { success => 1 } ] };
}

sub add_user {
    my $method = shift;
    my $params = shift;
    my $ref = shift;

    my $entity = OESS::Entity->new(db => $db, entity_id => $params->{entity_id}{value});
    if (!defined $entity) {
        $method->set_error("Unable to find entity $params->{'entity_id'}{'value'} in the db.");
        return;
    }

    if (!_may_modify_entity($username, $entity)) {
        $method->set_error('Entity may not be modified by current user.');
        return;
    }

    my $user = OESS::User->new(db => $db, user_id => $params->{user_id}{value});
    if (!defined $user) {
        $method->set_error("Unable to find user $params->{'user_id'}{'value'} in the db.");
        return;
    }

    $entity->add_user($user);
    my $err = $entity->update_db();
    if (defined $err) {
        $method->set_error("$err");
        return;
    }

    return { results => [ { success => 1 } ] };
}

sub remove_user {
    my $method = shift;
    my $params = shift;
    my $ref = shift;

    my $entity = OESS::Entity->new(db => $db, entity_id => $params->{entity_id}{value});
    if (!defined $entity) {
        $method->set_error("Unable to find entity $params->{'entity_id'}{'value'} in the db.");
        return;
    }

    if (!_may_modify_entity($username, $entity)) {
        $method->set_error('Entity may not be modified by current user.');
        return;
    }

    my $user = OESS::User->new(db => $db, user_id => $params->{user_id}{value});
    if (!defined $user) {
        $method->set_error("Unable to find user $params->{'user_id'}{'value'} in the db.");
        return;
    }

    $entity->remove_user($user);
    my $err = $entity->update_db();
    if (defined $err) {
        $method->set_error("$err");
        return;
    }

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

sub get_entities{
    my $method = shift;
    my $params = shift;
    my $ref = shift;

    my $workgroup_id = $params->{'workgroup_id'}{'value'};

    my ($access, $err) = OESS::DB::User::has_workgroup_access(db => $db, username => $username, workgroup_id => $workgroup_id, role => 'read-only');
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $entities = OESS::DB::Entity::get_entities(db => $db, name => $params->{name}{value});
    my $results = [];
    foreach my $entity (@$entities) {
        my %vlans;
        my @ints;
        foreach my $int (@{$entity->interfaces()}){
            my $obj = $int->to_hash();
            my @allowed_vlans;

            foreach my $acl (@{$int->acls()}){
                next if (!defined $acl->{'entity_id'}) || ($acl->{'entity_id'} != $entity->entity_id);
                next if (!defined $acl->{'allow_deny'}) || ($acl->{'allow_deny'} ne 'allow');
                next if (defined($acl->{'workgroup_id'}) && $acl->{'workgroup_id'} != $workgroup_id);

                for (my $i=$acl->{'start'}; $i<=$acl->{'end'}; $i++) {
                    if ($int->vlan_valid(workgroup_id => $workgroup_id, vlan => $i)) {
                        $obj->{'available_vlans'} = \@allowed_vlans;
                        push(@ints,$obj);
                        last;
                    }
                }
            }
        }

        my @uniq_ints;
        foreach my $int (@ints){
            my $found = 0;
            foreach my $uint (@uniq_ints){
                if($uint->{'interface_id'} == $int->{'interface_id'}){
                    $found = 1;
                }
            }
            if(!$found){
                push(@uniq_ints, $int);
            }
        }

        my $result = $entity->to_hash();
        $result->{interfaces} = \@uniq_ints;

        push @$results, $result;
    }

    return { results => $results };
}

sub get_entity_children{
    my $method = shift;
    my $params = shift;
    my $ref = shift;
    
    my $entity = OESS::Entity->new(db => $db, entity_id => $params->{'entity_id'}{'value'});

    if(!defined($entity)){
        $method->set_error("Unable to find entity: " . $params->{'entity_id'}{'value'} . " in the Database.");
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
    
    my $vrf_id = $params->{'vrf_id'}{'value'};
    my $circuit_id = $params->{'circuit_id'}{'value'};
    #verify user is in workgroup
    my $user = OESS::DB::User::find_user_by_remote_auth( db => $db, remote_user => $ENV{'REMOTE_USER'} );
    $user = OESS::User->new(db => $db, user_id =>  $user->{'user_id'} );
       if(!defined($user)){
        $method->set_error("User " . $ENV{'REMOTE_USER'} . " is not in OESS");
        return;
    }
    my $workgroup_id = $params->{'workgroup_id'}{'value'};
    my ($access, $err) = OESS::DB::User::has_workgroup_access(db => $db, username => $username, workgroup_id => $workgroup_id, role => 'read-only');
    if (defined $err) {
        $method->set_error($err);
        return;
    } 
    my $entity = OESS::Entity->new(db => $db, entity_id => $params->{'entity_id'}{'value'});

    if(!defined($entity)){
        $method->set_error("Entity was not found in the database.");
        return;
    }

    if(!$user->in_workgroup( $workgroup_id) && !$user->is_admin()){
        $method->set_error("User not in workgroup.");
        return;
    }

    my %vlans;

    my $vrf;
    my $circuit;


    if(defined($vrf_id)){
        $vrf = OESS::VRF->new(db => $db, vrf_id => $vrf_id);
        if(!defined($vrf)){
            $method->set_error("Unable to find VRF: " . $vrf_id);
            return;
        }
    }

    if(defined($circuit_id)){
        $circuit = OESS::Circuit->new(db => $db, circuit_id => $vrf_id);
        if(!defined($circuit)){
            $method->set_error("Unable to find Circuit: " . $circuit_id);
            return;
        }
    }


    my @ints;
    foreach my $int (@{$entity->interfaces()}){
        my $already_used_tag;
        if(defined($vrf)){
            foreach my $ep (@{$vrf->endpoints}){
                if($ep->interface()->interface_id() == $int->interface_id()){
                    $already_used_tag = $ep->tag();
                }
            }
        }

        if(defined($circuit)){
            foreach my $ep (@{$circuit->endpoints}){
                if($ep->interface()->interface_id() == $int->interface_id()){
                    $already_used_tag = $ep->tag();
                }
            }
        }
        
        my $obj = $int->to_hash();
        my @allowed_vlans;

        foreach my $acl (@{$int->acls()}){
            next if $acl->{'entity_id'} != $entity->entity_id();
            next if $acl->{'allow_deny'} ne 'allow';
            next if (defined($acl->{'workgroup_id'}) && $acl->{'workgroup_id'} != $workgroup_id);
            for(my $i=$acl->{'start'}; $i<=$acl->{'end'}; $i++){
                if($int->vlan_valid( workgroup_id => $workgroup_id, vlan => $i )){
                    push(@allowed_vlans,$i);
                    $vlans{$i} = 1;
                }
                
                if(defined $already_used_tag && $already_used_tag == $i){
                    push(@allowed_vlans, $i);
                    $vlans{$i} = 1;
                }
            }
            $obj->{'available_vlans'} = \@allowed_vlans;
            push(@ints,$obj);
        }
    }
    
    if(defined($vrf_id)){
        my $vrf = OESS::VRF->new(db => $db, vrf_id => $vrf_id);
        if(!defined($vrf)){
            $method->set_error("Unable to find VRF: " . $vrf_id);
            return;
        }
        
        foreach my $ep (@{$vrf->endpoints()}){
            warn "Entity ID: " . $ep->entity->entity_id() . " vs " . $entity->entity_id() . "\n";
            if($ep->entity->entity_id() == $entity->entity_id()){
                warn "Adding Tag: " . $ep->tag() . "\n";
                $vlans{$ep->tag()} = 1;
            }
        }
    }

    my @uniq_ints;
    foreach my $int (@ints){
        my $found = 0;
        foreach my $uint (@uniq_ints){
            if($uint->{'interface_id'} == $int->{'interface_id'}){
                $found = 1;
            }
        }
        if(!$found){
            push(@uniq_ints, $int);
        }
    }

    my $res = $entity->to_hash();
    $res->{'interfaces'} = \@uniq_ints;
    my @allowed_vs = keys %vlans;
    $res->{'allowed_vlans'} = \@allowed_vs;
    return {results => $res};
}

sub get_valid_users{
    my $method = shift;
    my $params = shift;

    my $entity_id = $params->{'entity_id'}{'value'};
    my $users = $db->execute_query("SELECT user_id from user_entity_membership WHERE entity_id =$entity_id");
    my @res;
    my @users;
    foreach my $var  (@$users){
        push(@res, $var->{'user_id'});
    }
    return {results => \@res};
}

sub add_child_entity {
    my $method = shift;
    my $params = shift;

    my $entity = OESS::Entity->new(db => $db, entity_id => $params->{'current_entity_id'}{'value'});
    if (!defined $entity) {
        $method->set_error("Unable to find entity $params->{'entity_id'}{'value'} in the db.");
        return;
    }

    if (!_may_modify_entity($username, $entity)) {
        $method->set_error('Entity may not be modified by current user.');
        return;
    }

   my $child_id = $entity->create_child_entity(
                name =>  $params->{name}{value},
                description =>  $params->{description}{value},
                logo_url =>  $params->{logo_url}{value},
                url =>  $params->{url}{value},
		user_id => $params->{'user_id'}{'value'}
              ); 
    if (!defined $child_id){
        $method->set_error("Unable to add child.");
        return;
    }
    return { results => [ { success => 1, child_entity_id => $child_id } ] };
}

sub _may_modify_entity {
    my $user_name = shift;
    my $entity = shift;

    my $user_id = OESS::DB::User::find_user_by_remote_auth(db => $db, remote_user => $user_name);
    $user_id = $user_id->{'user_id'};

    return 0 if !defined($user_id);

    # If the user is a member of the entity, they may modify it:
    return 1 if any { defined($_->user_id()) && ($_->user_id() == $user_id) } @{$entity->users()};

    # Else, if the user is an admin, they may modify the entity:
    my $user = OESS::User->new(db => $db, user_id => $user_id);
    return 0 if !defined($user);
    my ($access, $err) = OESS::DB::User::has_system_access(db => $db, username => $username, role => 'normal');
    return $access;
}

sub main{
    register_ro_methods();
    register_rw_methods();
    
    $svc->handle_request();
}

main();
