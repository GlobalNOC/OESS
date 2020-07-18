#!/usr/bin/perl

use strict;
use warnings;

package OESS::User;

use Data::Dumper;

use OESS::DB::User;
use OESS::Workgroup;

=head2 new

=cut
sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.User");

    my %args = (
        user_id => undef,
        username => undef,
        db => undef,
        role => undef,
        @_
        );

    my $self = \%args;

    bless $self, $class;

    $self->{'logger'} = $logger;

    if (!defined $self->{'db'}) {
        $self->{'logger'}->error("No Database Object specified");
        return;
    }

    my $ok = $self->_fetch_from_db();
    if (!$ok) {
        return;
    }

    return $self;
}

=head2 to_hash

=cut
sub to_hash{
    my $self = shift;

    my $obj = {};

    $obj->{'username'} = $self->username();
    $obj->{'first_name'} = $self->first_name();
    $obj->{'last_name'} = $self->last_name();
    $obj->{'email'} = $self->email();
    $obj->{'user_id'} = $self->user_id();
    $obj->{'is_admin'} = $self->is_admin();
    
    if (defined $self->{workgroups}) {
        $obj->{'workgroups'} = [];
        foreach my $wg (@{$self->{workgroups}}) {
            push @{$obj->{workgroups}}, $wg->to_hash;
        }
    }
    if (defined $self->{'role'}) {
        $obj->{role} = $self->roll();
    }
    return $obj;
}

=head2 from_hash

=cut
sub from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{'user_id'} = $hash->{'user_id'};
    $self->{'username'} = $hash->{'username'};
    $self->{'first_name'} = $hash->{'given_names'};
    $self->{'last_name'} = $hash->{'family_name'};
    $self->{'email'} = $hash->{'email'};
    $self->{'is_admin'} = $hash->{'is_admin'};
    if (defined $hash->{'role'}) {
        $self->{'role'} = $hash->{'role'};
    }
    if (defined $hash->{workgroups}) {
        $self->{'workgroups'} = $hash->{'workgroups'};
    }

    return 1;
}

=head2 _fetch_from_db

=cut
sub _fetch_from_db{
    my $self = shift;

    my $user = OESS::DB::User::fetch(
        db => $self->{'db'},
        user_id => $self->{'user_id'},
        username => $self->{'username'},
        role => $self->{'role'}
    );
    if (!defined $user) {
        return;
    }

    return $self->from_hash($user);
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

=head2 username

=cut
sub username{
    my $self = shift;
    return $self->{'username'};
}

=head2 first_name

=cut
sub first_name{
    my $self = shift;
    return $self->{'first_name'};
}

=head2 last_name

=cut
sub last_name{
    my $self = shift;
    return $self->{'last_name'};

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
sub is_admin{
    my $self = shift;
    return $self->{'is_admin'};
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

1;
