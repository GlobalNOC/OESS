#!/usr/bin/perl

use strict;
use warnings;

package OESS::User;

use Data::Dumper;

use OESS::DB::User;
use OESS::Workgroup;

=head2 new

=cut
sub new {
    my $class = shift;
    my $args  = {
        db      => undef,
        user_id => undef,
        model   => undef,
        logger  => Log::Log4perl->get_logger("OESS.User"),
        @_
    };
    my $self = bless $args, $class;

    $self->{usernames_to_add} = [];
    $self->{usernames_to_remove} = [];

    if (defined $self->{db} && (defined $self->{user_id} || defined $self->{username})) {
        my $err;
        ($self->{model}, $err) = OESS::DB::User::fetch_v2(
            db       => $self->{db},
            user_id  => $self->{user_id},
            username => $self->{username}
        );
        warn $err if defined $err;
    }
    return if !defined $self->{model};

    $self->from_hash($self->{model});
    return $self;
}

=head2 to_hash

=cut
sub to_hash {
    my $self = shift;

    my $obj = {};

    $obj->{'usernames'} = $self->usernames();
    $obj->{'first_name'} = $self->first_name();
    $obj->{'last_name'} = $self->last_name();
    $obj->{'email'} = $self->email();
    $obj->{'user_id'} = $self->user_id();
    $obj->{'is_admin'} = 0;
    $obj->{'status'} = $self->{'status'};

    if (defined $self->{workgroups}) {
        $obj->{'workgroups'} = [];
        foreach my $wg (@{$self->{workgroups}}) {
            $obj->{'is_admin'} = 1 if $wg->type eq 'admin';
            push @{$obj->{workgroups}}, $wg->to_hash;
        }
    }
    if (defined $self->{'role'}) {
        $obj->{role} = $self->role();
    }
    return $obj;
}

=head2 from_hash

=cut
sub from_hash {
    my $self = shift;
    my $hash = shift;

    $self->{email}      = $hash->{email};
    $self->{first_name} = $hash->{first_name};
    $self->{last_name}  = $hash->{last_name};
    $self->{user_id}    = $hash->{user_id};
    $self->{usernames}  = $hash->{usernames};
    $self->{status}     = $hash->{status};

    if (defined $hash->{workgroups}) {
        $self->{workgroups} = $hash->{workgroups};
    }
    if (defined $hash->{usernames}) {
        $self->{usernames} = $hash->{usernames};
    }
    return 1;
}

=head2 create

=cut
sub create {
    my $self = shift;

    if (!defined $self->{db}) {
        return (undef, "Couldn't create User. Database handle is missing.");
    }

    my ($id, $err) = OESS::DB::User::add_user(
        db          => $self->{db},
        email       => $self->{model}->{email},
        family_name => $self->{model}->{last_name},
        given_name  => $self->{model}->{first_name},
        auth_names  => $self->{model}->{username}
    );
    if (defined $err) {
        return (undef, $err);
    }

    $self->{user_id} = $id;
    return ($id, undef);
}

=head2 update

=cut
sub update {
    my $self = shift;

    if (!defined $self->{db}) {
        $self->{logger}->error("Couldn't update User: DB handle is missing.");
        return "Couldn't update User: DB handle is missing.";
    }

    my $uerr = OESS::DB::User::update(
        db         => $self->{db},
        user_id    => $self->{user_id},
        first_name => $self->{first_name},
        last_name  => $self->{last_name},
        email      => $self->{email}
    );
    return $uerr if defined $uerr;

    foreach my $username (@{$self->{usernames_to_add}}) {
        my $err = OESS::DB::User::add_username(
            db       => $self->{db},
            user_id  => $self->{user_id},
            username => $username
        );
        return $err if defined $err;
    }

    foreach my $username (@{$self->{usernames_to_remove}}) {
        my $err = OESS::DB::User::remove_username(
            db       => $self->{db},
            username => $username
        );
        return $err if defined $err;        
    }

    return;
}

=head2 load_workgroups

=cut
sub load_workgroups {
    my $self = shift;

    my ($datas, $err) = OESS::DB::User::get_workgroups(
        db => $self->{db},
        user_id => $self->{user_id}
    );
    if (defined $err) {
        $self->{logger}->error($err);
        return;
    }

    $self->{workgroups} = [];
    foreach my $data (@$datas){
        push @{$self->{workgroups}}, OESS::Workgroup->new(db => $self->{db}, model => $data);
    }

    return;
}

=head2 get_workgroup

    my $wg = $user->get_workgroup(
        workgroup_id => 100
    );

get_workgroup returns the Workgroup identified by C<workgroup_id>.

=cut
sub get_workgroup {
    my $self = shift;
    my $args = {
        workgroup_id => undef,
        @_
    };

    if (!defined $args->{workgroup_id}) {
        return;
    }

    foreach my $workgroup (@{$self->{workgroups}}) {
        if ($workgroup->workgroup_id == $args->{workgroup_id}) {
            return $workgroup;
        }
    }

    return;
}

=head2 usernames

=cut
sub usernames {
    my $self = shift;
    return $self->{usernames};
}

=head2 add_username

=cut
sub add_username {
    my $self = shift;
    my $name = shift;

    foreach my $username (@{$self->{usernames}}) {
        return if ($username eq $name);
    }

    push @{$self->{usernames_to_add}}, $name;
    push @{$self->{usernames}}, $name;
    return;
}

=head2 remove_username

=cut
sub remove_username {
    my $self = shift;
    my $name = shift;

    my $usernames = [];
    foreach my $username (@{$self->{usernames}}) {
        if ($username eq $name) {
            push @{$self->{usernames_to_remove}}, $name;
        } else {
            push @$usernames, $username;
        }
    }
    $self->{usernames} = $usernames;
    return;
}

=head2 has_username

=cut
sub has_username {
    my $self = shift;
    my $username = shift;

    foreach my $name (@{$self->{usernames}}) {
        return 1 if $name eq $username;
    }
    return 0;
}

=head2 first_name

=cut
sub first_name {
    my $self = shift;
    my $name = shift;
    if (defined $name) {
        $self->{first_name} = $name;
    }
    return $self->{first_name};
}

=head2 last_name

=cut
sub last_name {
    my $self = shift;
    my $name = shift;
    if (defined $name) {
        $self->{last_name} = $name;
    }
    return $self->{last_name};
}

=head2 user_id

=cut
sub user_id{
    my $self = shift;
    return $self->{'user_id'};
    
}

=head2 workgroups

=cut
sub workgroups{
    my $self = shift;
    return $self->{'workgroups'} || [];
}

=head2 role

=cut
sub role{
    my $self = shift;
    my $role = shift;

    if (defined $role) {
        $self->{role} = $role;
    }
    return $self->{role};
}

=head2 email

=cut
sub email{
    my $self = shift;
    return $self->{'email'};
}

=head2 is_admin

=cut
sub is_admin {
    my $self = shift;
    foreach my $wg (@{$self->{workgroups}}) {
        return 1 if $wg->type eq 'admin';
    }
    return 0;
}

=head2 in_workgroup

=cut
sub in_workgroup{
    my $self = shift;
    my $workgroup_id = shift;

    $self->load_workgroups if !defined $self->{workgroups};

    foreach my $wg (@{$self->workgroups()}){
        if($wg->workgroup_id() == $workgroup_id){
            return 1;
        }
    }
    return 0;
}

=head2 has_workgroup_access

=cut
sub has_workgroup_access {
    my $self = shift;
    my $args = {
        role         => undef,
        workgroup_id => undef,
        @_
    };

    my $ok;
    my $err;
    foreach my $username (@{$self->{usernames}}) {
        ($ok, $err) = OESS::DB::User::has_workgroup_access(
            db           => $self->{db},
            role         => $args->{role},
            username     => $username,
            workgroup_id => $args->{workgroup_id}
        );
        if ($ok) { return (1, undef); }
    }
    return (0, $err);
}

=head2 has_system_access

=cut
sub has_system_access {
    my $self = shift;
    my $args = {
        role => undef,
        @_
    };

    my $ok;
    my $err;
    foreach my $username (@{$self->{usernames}}) {
        ($ok, $err) = OESS::DB::User::has_system_access(
            db       => $self->{db},
            role     => $args->{role},
            username => $username
        );
        if ($ok) { return (1, undef); }
    }
    return (0, $err);
}

1;
