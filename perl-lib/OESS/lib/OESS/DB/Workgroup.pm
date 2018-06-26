#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::Workgroup;

sub fetch{
    my %params = @_;
    my $db = $params{'db'};
    my $workgroup_id = $params{'workgroup_id'};

    my $wg = $db->execute_query("select * from workgroup where workgroup_id = ?",[$workgroup_id]);
    if(!defined($wg) || !defined($wg->[0])){
        return;
    }

    return $wg->[0];
}

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


1;
