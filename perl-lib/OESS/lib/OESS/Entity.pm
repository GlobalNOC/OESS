#!/usr/bin/perl

use strict;
use warnings;

package OESS::Entity;

use Log::Log4perl;

use OESS::DB::Endpoint;
use OESS::DB::Entity;
use OESS::User;

=head1 OESS::Entity

    use OESS::Entity

=cut

=head2 new

    my $entity = new OESS::Entity(
        db => $db,
        entity_id => 100
    );

    # or

    my $entity = new OESS::Entity(
        db => $db,
        name => 'entity name'
    );

    # or

    my $entity = new OESS::Entity(
        db => $db,
        interface_id => 100,
        vlan => 1200
    );

    # or

    my $entity = new OESS::Entity(
        model => {
            name        => 'name'
            description => 'description'
            logo_url    => 'https://...'
            url         => 'https://...'
            interfaces  => [],           # Optional
            parents     => [],           # Optional
            children    => [],           # Optional
            entity_id   => 100,          # Optional
            users       => []            # Optional
        }
    );

new creates a new Entity object loaded from the database or the
C<model> hash. For flexibility, nn Entity may be loaded by
C<entity_id>, C<name>, or <Cinterface_id> and C<vlan>.

=cut
sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my %args = (
        db           => undef,
        name         => undef,
        entity_id    => undef,
        interface_id => undef,
        vlan         => undef,
        model        => undef,
        logger       => Log::Log4perl->get_logger("OESS.Entity"),
        reservations => {},
        @_
    );

    my $self = \%args;

    bless $self, $class;

    if (!defined $self->{'db'}) {
        $self->{'logger'}->warn("No Database Object specified");
    }

    my $by_id = defined $self->{entity_id};
    my $by_name = defined $self->{name};
    my $by_vlan = (defined $self->{interface_id} && defined $self->{vlan});

    if (defined $self->{db} && ($by_id || $by_name || $by_vlan)) {
        my $fetch_ok = $self->_fetch_from_db();
        return undef if !$fetch_ok;

    } elsif (defined $self->{model}) {
        $self->_from_hash($self->{model});

    } else {
        return undef;
    }

    return $self;
}

=head2 _from_hash

=cut
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

=head2 _fetch_from_db

=cut
sub _fetch_from_db{
    my $self = shift;

    my $info = OESS::DB::Entity::fetch(
        db => $self->{'db'},
        entity_id => $self->{'entity_id'},
        name => $self->{'name'},
        interface_id => $self->{'interface_id'},
        vlan => $self->{'vlan'}
    );
    return 0 if !defined($info);

    $self->_from_hash($info);
    return 1;
}

=head2 update_db

=cut
sub update_db{
    my $self = shift;

    my $entity = $self->to_hash();

    $self->{db}->start_transaction();

    my $result = OESS::DB::Entity::remove_users(db => $self->{db}, entity => $entity);
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

=head2 to_hash

=cut
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

=head2 select_interface

=cut
sub select_interface {
    my $self = shift;
    my $args = {
        inner_tag        => undef,
        tag              => undef,
        workgroup_id     => undef,
        cloud_account_id => undef,
        @_
    };

    if (!defined $self->{db}) {
        $self->{logger}->warn('Interface selection may not return accurate results as database object not defined.');
    }

    # Get number of Endpoints using the provided azure service key.
    # If cloud_account_id is already in use on another endpoint we'll
    # want to select the interface associated with the secondary azure
    # port. If the cloud_account_id is already in use on both the
    # primary and secondary the service key may no longer be used.
    my $cloud_account_ep_count = 0;
    if (defined $args->{cloud_account_id} && $args->{cloud_account_id} ne '' && defined $self->{db}) {
        my ($eps, $eps_err) = OESS::DB::Endpoint::fetch_all(db => $self->{db}, cloud_account_id => $args->{cloud_account_id});
        if (defined $eps_err) {
            $self->{logger}->error($eps_err);
            return undef;
        }
        $cloud_account_ep_count = (defined $eps) ? scalar @$eps : 0;
        warn "$cloud_account_ep_count Endpoints used with this cloud_account_id";
    }

    foreach my $intf (@{$self->{interfaces}}) {
        if (defined $intf->cloud_interconnect_type && $intf->cloud_interconnect_type eq 'gcp-partner-interconnect') {
            if (!defined $args->{cloud_account_id}) {
                return undef;
            }

            my @part = split(/\//, $args->{cloud_account_id});
            my $key_zone = 'zone' . $part[2];

            @part = split(/-/, $intf->cloud_interconnect_id);
            my $conn_zone = $part[4];

            if ($conn_zone ne $key_zone) {
                next;
            }
        }

        if (defined $intf->cloud_interconnect_type && $intf->cloud_interconnect_type eq 'azure-express-route') {
            if (!defined $args->{cloud_account_id}) {
                warn 'Azure Service key was not provided.';
                return undef;
            }

            if ($intf->cloud_interconnect_id =~ /PRI/ && $cloud_account_ep_count == 0) {
                # Only select if interface contains 'PRI'
                warn 'Selecting primary Azure port.';
            }
            elsif ($intf->cloud_interconnect_id =~ /SEC/ && $cloud_account_ep_count == 1) {
                # Only select if interface contains 'SEC'
                warn 'Selecting secondary Azure port.';
            }
            else {
                next;
            }
        }

        my $ok = $intf->vlan_valid(
            vlan => $args->{tag},
            workgroup_id => $args->{workgroup_id}
        );
        if ($ok) {
            # Register selected vlans as being in use so that
            # successive calls to the same entity with the same vlan
            # yield different interfaces.

            if (!defined $self->{reservations}->{$intf->{interface_id}}) {
                $self->{reservations}->{$intf->{interface_id}} = {};
            }
            if (!defined $self->{reservations}->{$intf->{interface_id}}->{$args->{tag}}) {
                $self->{reservations}->{$intf->{interface_id}}->{$args->{tag}} = 1;
                return $intf;
            }
        }
    }
    return undef;
}

=head2 users

=cut
sub users {
    my $self = shift;

    return $self->{'users'} || [];
}

=head2 entity_id

=cut
sub entity_id{
    my $self = shift;
    return $self->{'entity_id'};
}

=head2 name

=cut
sub name{
    my $self = shift;
    my $name = shift;
    if(defined($name)){
        $self->{'name'} = $name;
    }else{
        return $self->{'name'};
    }
}

=head2 description

=cut
sub description{
    my $self = shift;
    my $description = shift;

    if(defined($description)){
        $self->{'description'} = $description;
    }
    return $self->{'description'};
}

=head2 logo_url

=cut
sub logo_url{
    my $self = shift;
    my $logo_url = shift;

    if(defined($logo_url)){
        $self->{'logo_url'} = $logo_url;
    }
    return $self->{'logo_url'};
}

=head2 url

=cut
sub url {
    my $self = shift;
    my $url = shift;
    if(defined($url)){
        $self->{'url'} = $url;
    }
    return $self->{'url'};
}

=head2 interfaces

=cut
sub interfaces{
    my $self = shift;
    my $interfaces = shift;
    
    if(defined($interfaces)){
        $self->{'interfaces'} = $interfaces;
    }else{    
        return $self->{'interfaces'};
    }
}

=head2 parents

=cut
sub parents{
    my $self = shift;
    my $parents = shift;
    if(defined($parents)){
        $self->{'parents'} = $parents;
    }else{
        return $self->{'parents'};
    }
}

=head2 children

=cut
sub children{
    my $self = shift;
    my $children = shift;

    if(defined($children)){
        $self->{'children'} = $children;
    }else{
        return $self->{'children'};
    }
}

=head2 add_child

=cut
sub add_child{
    my $self = shift;
    my $entity = shift;

    push(@{$self->{'children'}},$entity);
}

=head2 add_parent

=cut
sub add_parent{
    my $self = shift;
    my $entity = shift;

    push(@{$self->{'parents'}},$entity);
}

=head2 add_interface

=cut
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

=head2 remove_interface

=cut
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

=head2 add_user

=cut
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

=head2 remove_user

=cut
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

=head2 create_child_entity

=cut
sub create_child_entity {
    my $self = shift;
    my %params = @_;
    my $name = $params{'name'};
    my $description = $params{'description'};
    my $logo_url = $params{'logo_url'};
    my $url = $params{'url'};

    $self->{db}->start_transaction();
    my $child_id = OESS::DB::Entity::create_entity(db => $self->{db},
                                    name => $name,
                                    description => $description,
                                    logo_url => $logo_url,
                                    url=> $url );
   
    if (!defined ($child_id)){
      $self->{db}->rollback();
      warn $self->{db}->{error};
      return;
      }
    $self->{db}->commit();

    my $child_entity = OESS::Entity->new(db => $self->{db}, entity_id => $child_id);
    if (!defined $child_entity) {
      warn "Unable to find child entity $child_entity in the db";
      return;
    }

    # Add User to the child first
    my $user = OESS::User->new(db => $self->{db}, user_id => $params{user_id});
    if (!defined $user) {
        warn "Unable to find user $params{'user_id'} in the db.";
        return;
    }
    $child_entity->add_user($user);

    my $err_child = $child_entity->update_db();
    if (defined $err_child) {
        warn "$err_child";
        return;
    }

    $self->add_child($child_entity);
    my $err = $self->update_db();
    if (defined ($err)){
      warn "Unable to add child";
      return;
    }
   
   return $child_id;
}

1;
