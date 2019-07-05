#!/usr/bin/perl

use strict;
use warnings;

use OESS::User;
use OESS::Interface;

package OESS::DB::Workgroup;

=head2 fetch

=cut
sub fetch{
    my %params = @_;
    my $db = $params{'db'};
    my $workgroup_id = $params{'workgroup_id'};
    
    my $wg = $db->execute_query("select * from workgroup where workgroup_id = ?",[$workgroup_id]);
    if(!defined($wg) || !defined($wg->[0])){
        return;
    }
    
    my @ints;
    my $interfaces = $db->execute_query("select interface_id from interface where workgroup_id = ?",[$workgroup_id]);
    $wg->[0]->{'interfaces'} = $interfaces;
    
    return $wg->[0];
}

=head2 get_users_in_workgroup

=cut
sub get_users_in_workgroup{
    my %params = @_;
    
    my $db = $params{'db'};
    my $workgroup_id = $params{'workgroup_id'};
    
    my $users = $db->execute_query("select user_id from user_workgroup_membership where workgroup_id = ?",[$workgroup_id]);
    if(!defined($users)){
        return;
    }
    
    my @users;
    
    foreach my $u (@$users){
        my $user = OESS::User->new(db => $db, user_id => $u->{'user_id'});
        if(!defined($user)){
            next;
        }
        
        push(@users, $user);
    }
    return \@users;
}

=head2 create

=cut
sub create {
    my $args = {
        db    => undef,
        model => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `model` is missing.') if !defined $args->{model};
    return (undef, 'Required argument `model->name` is missing.') if !defined $args->{model}->{name};
    return (undef, 'Required argument `model->description` is missing.') if !exists $args->{model}->{description};

    $args->{model}->{type} = $args->{model}->{type} || 'normal';

    my $q = "
        INSERT INTO workgroup (name, description, external_id, type)
        VALUES (?, ?, ?, ?)
    ";
    my $workgroup_id = $args->{db}->execute_query($q, [
        $args->{model}->{name},
        $args->{model}->{description},
        $args->{model}->{external_id},
        $args->{model}->{type}
    ]);
    if (!defined $workgroup_id) {
        return (undef, $args->{db}->get_error);
    }

    return ($workgroup_id, undef);
}

1;
