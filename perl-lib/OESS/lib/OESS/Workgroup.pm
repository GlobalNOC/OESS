#!/usr/bin/perl

use strict;
use warnings;

package OESS::Workgroup;

use OESS::DB::Workgroup;
use Data::Dumper;

=head2 new

=cut
sub new {
    my $that  = shift;
    my $class = ref($that) || $that;

    my $self = {
        workgroup_id => undef,
        db     => undef,
        modal  => undef,
        logger => Log::Log4perl->get_logger("OESS.Workgroup"),
        @_
    };
    bless $self, $class;

    if (defined $self->{db} && defined $self->{workgroup_id}) {
        $self->{model} = OESS::DB::Workgroup::fetch(
            db => $self->{db},
            workgroup_id => $self->{workgroup_id}
        );
    }

    if (!defined $self->{model}) {
        return;
    }

    $self->from_hash($self->{model});
    return $self;
}

=head2 from_hash

=cut
sub from_hash {
    my $self = shift;
    my $hash = shift;

    $self->{workgroup_id} = $hash->{workgroup_id};
    $self->{name}         = $hash->{name};
    $self->{description}  = $hash->{description};
    $self->{type}         = $hash->{type};
    $self->{max_circuits} = $hash->{max_circuits};
    $self->{external_id}  = $hash->{external_id};
    if(defined $hash->{role}){
        $self->{role} = $hash->{role};
    }
    foreach my $i (@{$hash->{interfaces}}) {
        push @{$self->{interfaces}}, new OESS::Interface(db => $self->{db}, interface_id => $i->{interface_id});
    }

    foreach my $u (@{$hash->{users}}) {
        push @{$self->{users}}, new OESS::User(db => $self->{db}, user_id => $u->{user_id});
    }
}

=head2 to_hash

=cut
sub to_hash {
    my $self = shift;
    my $hash = {};

    $hash->{workgroup_id} = $self->{workgroup_id};
    $hash->{name}         = $self->{name};
    $hash->{description}  = $self->{description};
    $hash->{type}         = $self->{type};
    $hash->{status}       = $self->{status};
    $hash->{max_circuits} = $self->{max_circuits};
    $hash->{external_id}  = $self->{external_id};
    $hash->{interfaces}   = [] if defined $self->{interfaces};
    $hash->{users}        = [] if defined $self->{users};
    $hash->{role}         = $self->{role} if defined $self->{role};
    if (defined $self->{interfaces}) {
        foreach my $i (@{$self->{interfaces}}) {
            push @{$hash->{interfaces}}, $i->to_hash;
        }
    }

    if (defined $self->{users}) {
        foreach my $u (@{$self->{users}}) {
            push @{$hash->{users}}, $u->to_hash;
        }
    }

    return $hash;
}

=head2 create

=cut
sub create {
    my $self = shift;

    if (!defined $self->{db}) {
        return (undef, "Couldn't create Workgroup: DB handle is missing.");
    }

    my ($workgroup_id, $err) = OESS::DB::Workgroup::create(
        db => $self->{db},
        model => $self->to_hash
    );
    if (defined $err) {
        return (undef, $err);
    }

    if (defined $self->{users}) {
        foreach my $user (@{$self->{users}}) {
            my ($ok, $user_wg_err) = OESS::DB::Workgroup::add_user(
                db           => $self->{db},
                workgroup_id => $workgroup_id,
                user_id      => $user->user_id
            );
            if (defined $user_wg_err) {
                return (undef, $user_wg_err);
            }
        }
    }

    $self->{workgroup_id} = $workgroup_id;
    return ($workgroup_id, undef);
}

=head2 update

    my $err = $workgroup->update;
    $db->rollback if (defined $err);

update saves any changes made to this Workgroup and maintains user
relationships based on calls to C<add_user> and C<remove_user>.

Note that any changes to the underlying User objects will not be
propagated to the database by this method call. We maintain the object
structure, Workgroup details, and User-to-Workgroup
relationships. B<Nothing else.>

=cut
sub update {
    my $self = shift;
    my $args = {
        @_
    };

    if (!defined $self->{db}) {
        $self->{logger}->error("Couldn't update Workgroup: DB handle is missing.");
        return "Couldn't update Workgroup: DB handle is missing.";
    }

    foreach my $user_id (@{$self->{users_to_remove}}) {
        my ($rm_ok, $rm_err) = OESS::DB::Workgroup::remove_user(
            db => $self->{db},
            user_id => $user_id,
            workgroup_id => $self->workgroup_id
        );
        return $rm_err if (defined $rm_err);
    }

    foreach my $user_id (@{$self->{users_to_add}}) {
        my ($create_ok, $create_err) = OESS::DB::Workgroup::add_user(
            db => $self->{db},
            user_id => $user_id,
            workgroup_id => $self->workgroup_id
        );
        return $create_err if (defined $create_err);
    }
    my ($ok,$err) = OESS::DB::Workgroup::update(
        db => $self->{'db'},
        model => $self->to_hash()
    );
    return $err if (defined $err);

    return;
}


=head2 max_circuits

=cut
sub max_circuits{
    my $self = shift;
    return $self->{'max_circuits'};
}

=head2 add_user

    $path->add_user($user);

add_user adds an C<OESS::User> to this Workgroup. If
C<$user->{user_id}> isn't defined, C<$this->update> will not save your
data.

=cut
sub add_user {
    my $self = shift;
    my $user = shift;

    push @{$self->{users_to_add}}, $user->user_id;
    push @{$self->{users}}, $user;
}

=head2 remove_user

    $path->remove_user($user_id);

remove_user removes the user identified by C<$user_id> from this
Workgroup.

=cut
sub remove_user {
    my $self = shift;
    my $user_id = shift;

    my $new_users = [];
    foreach my $user (@{$self->{users}}) {
        if ($user->user_id == $user_id) {
            push @{$self->{users_to_remove}}, $user_id;
        } else {
            push @$new_users, $user;
        }
    }
    $self->{users} = $new_users;
}

=head2 workgroup_id

=cut
sub workgroup_id{
    my $self = shift;
    my $workgroup_id = shift;

    if(!defined($workgroup_id)){
        return $self->{'workgroup_id'};
    }else{
        $self->{'workgroup_id'} = $workgroup_id;
        return $self->{'workgroup_id'};
    }
}

=head2 name

=cut
sub name{
    my $self = shift;
    my $name = shift;

    if(!defined($name)){
        return $self->{'name'};
    }else{
        $self->{'name'} = $name;
        return $self->{'name'};
    }
}

=head2 users

=cut
sub users {
    my $self = shift;
    return $self->{users};
}

=head2 interfaces

=cut
sub interfaces{
    my $self = shift;
    return $self->{interfaces};
}

=head2 type

=cut
sub type{
    my $self = shift;
    my $type = shift;

    if(!defined($type)){
        return $self->{'type'};
    }else{
        $self->{'type'} = $type;
        return $self->{'type'};
    }
}

=head2 external_id

=cut
sub external_id{
    my $self = shift;
    return $self->{'external_id'};
}

1;
