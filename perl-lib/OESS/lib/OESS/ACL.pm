#!/usr/bin/perl

use strict;
use warnings;

package OESS::ACL;

use Data::Dumper;
use OESS::DB::ACL;

=head2 new

    my $acl = OESS::ACL->new(db => $db, interface_acl_id => 1);

or

    my $acl = OESS::ACL->new(
        db => $db,
        model => {
            interface_acl_id => 1,           # Optional
            workgroup_id     => 1,
            interface_id     => 1,
            allow_deny       => 'allow',
            eval_position    => 10,
            start            => 100,
            end              => 120,
            notes            => 'group 1-A',
            entity_id        => 1
        }
    );

new creates a new ACL object. When created with a model,
C<interface_acl_id> may optionally be specified; This is useful if
you've already queried the raw data from the database.

=cut
sub new {
    my $class = shift;
    my $args  = {
        db           => undef,
        interface_id => undef,
        model        => undef,
        logger       => Log::Log4perl->get_logger('OESS.ACL'),
        @_
    };
    my $self = bless $args, $class;

    if (!defined $args->{db}) {
        $self->{logger}->warn('Optional argument `db` is missing.');
    } else {
        if (!defined $args->{interface_acl_id} && !defined $args->{model}) {
            die 'Required argument `interface_acl_id` or `model` is missing.';
        }
    }

    if (defined $self->{interface_acl_id}) {
        $self->_fetch_from_db();
    } else {
        $self->_build_from_model();
    }

    return $self;
}

=head2 _build_from_model

_build_from_model populates C<$self> from C<model> as defined in this
object's constructor. This method is only called when
C<interface_acl_id> is ommitted from the contructor.

=cut
sub _build_from_model {
    my $self = shift;

    $self->{interface_acl_id} = $self->{model}->{interface_acl_id};
    $self->{workgroup_id} = $self->{model}->{workgroup_id};
    $self->{workgroup_name} = $self->{model}->{workgroup_name};
    $self->{interface_id} = $self->{model}->{interface_id};
    $self->{allow_deny} = $self->{model}->{allow_deny};
    $self->{eval_position} = $self->{model}->{eval_position};
    $self->{start} = $self->{model}->{start};
    $self->{end} = (defined $self->{model}->{end}) ? $self->{model}->{end} : $self->{model}->{start};
    $self->{notes} = $self->{model}->{notes};
    $self->{entity_id} = $self->{model}->{entity_id};
    $self->{entity_name} = $self->{model}->{entity_name};

    return 1;
}

=head2 _fetch_from_db

_fetch_from_db populates C<$self> from the database when
C<interface_acl_id> is specified in this object's contructor.

=cut
sub _fetch_from_db {
    my $self = shift;

    my $acl = OESS::DB::ACL::fetch(db => $self->{db}, interface_acl_id => $self->{interface_acl_id});
    $self->from_hash($acl);
}

=head2 create

create inserts this object into the database as a new record. This
method will fail if C<< $self->{interface_acl_id} >> is
defined. Returns the new primary key on success.

=cut
sub create {
    my $self = shift;

    if (defined $self->{interface_acl_id}) {
        $self->{logger}->error('Cannot create an ACL database entry. Primary key already defined.');
        return 0;
    }

    my ($id, $err) = OESS::DB::ACL::create(db => $self->{db}, model => $self->to_hash());
    if (defined $err) {
        $self->{logger}->error($err);
        return 0;
    }

    $self->{interface_acl_id} = $id;
    return $id;
}

=head2 from_hash

from_hash populates this object from a simple perl hash as provided by
the database.

=cut
sub from_hash {
    my $self = shift;
    my $hash = shift;

    $self->{interface_acl_id} = $hash->{interface_acl_id};
    $self->{workgroup_id} = $hash->{workgroup_id};
    $self->{workgroup_name} = $hash->{workgroup_name};
    $self->{interface_id} = $hash->{interface_id};
    $self->{allow_deny} = $hash->{allow_deny};
    $self->{eval_position} = $hash->{eval_position};
    $self->{start} = $hash->{start};
    $self->{end} = (defined $hash->{end}) ? $hash->{end} : $hash->{start};
    $self->{notes} = $hash->{notes};
    $self->{entity_id} = $hash->{entity_id};
    $self->{entity_name} = $hash->{entity_name};

    return 1;
}

=head2 to_hash

to_hash converts this object to a simple perl hash.

=cut
sub to_hash {
    my $self = shift;
    my $hash = {};

    $hash->{interface_acl_id} = $self->{interface_acl_id};
    $hash->{workgroup_id} = $self->{workgroup_id};
    $hash->{workgroup_name} = $self->{workgroup_name};
    $hash->{interface_id} = $self->{interface_id};
    $hash->{allow_deny} = $self->{allow_deny};
    $hash->{eval_position} = $self->{eval_position};
    $hash->{start} = $self->{start};
    $hash->{end} = (defined $self->{end}) ? $self->{end} : $self->{start};
    $hash->{notes} = $self->{notes};
    $hash->{entity_id} = $self->{entity_id};
    $hash->{entity_name} = $self->{entity_name};

    return $hash;
}

=head2 vlan_allowed

vlan_allowed returns C<1> if C<workgroup_id> is authorized to
provision C<vlan> on C<< $self->{interface_id} >>. Returns C<0> if
C<workgroup_id> is explicitly denied access to C<vlan> on C<<
$self->{interface_id} >>. Otherwise this method returns C<-1>.

=cut
sub vlan_allowed {
    my $self = shift;
    my $args = {
        workgroup_id => undef,
        vlan         => undef,
        @_
    };

    die 'Required argument `workgroup_id` is missing.' if !defined $args->{workgroup_id};
    die 'Required argument `vlan` is missing.' if !defined $args->{vlan};

    # If C<< $self->{workgroup_id} >> is defined the acl only applies
    # to that workgroup. If undef it applies to all workgroups.
    if (defined $self->{workgroup_id} && $self->{workgroup_id} != $args->{workgroup_id}) {
        # Implicit denial
        return -1;
    }

    if ($args->{vlan} > $self->{end} || $args->{vlan} < $self->{start}) {
        # Implicit denial
        return -1;
    }

    if ($self->{allow_deny} eq 'deny') {
        # Explicit denial
        return 0;
    }

    # Selected workgroup_id, vlan range, and state is allow
    return 1;
}

=head2 update_db

update_db writes this ACL to the database. If the C<<
$self->{interface_acl_id} >> is not defined this call is delegated to
C<< $self->create >>. Returns 1 on success.

=cut
sub update_db {
    my $self = shift;

    if (!defined $self->{interface_acl_id}) {
        return $self->create();
    }

    my $acl = $self->to_hash();
    return OESS::DB::ACL::update(db => $self->{db}, acl => $acl);
}

=head2 interface_id

=cut
sub interface_id {
    my $self = shift;
    my $interface_id = shift;

    if (defined $interface_id) {
        $self->{interface_id} = $interface_id;
    }
    return $self->{interface_id};
}

return 1;
