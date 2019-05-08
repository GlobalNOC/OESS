#!/usr/bin/perl

use strict;
use warnings;

use OESS::Workgroup;

package OESS::DB::User;

=head2 fetch
=cut
sub fetch{
    my %params = @_;
    my $db = $params{'db'};
    my $user_id = $params{'user_id'};

    my $q = "
        select user.*, remote_auth.auth_name
        from user
        join remote_auth on user.user_id=remote_auth.user_id
        where user.user_id=?
    ";
    my $user = $db->execute_query($q, [$user_id]);
    if(!defined($user) || !defined($user->[0])){
        return;
    }


    $user = $user->[0];
    $user->{'workgroups'} = ();
    my $workgroups = $db->execute_query("select workgroup_id from user_workgroup_membership where user_id = ?",[$user_id]);
    $user->{'is_admin'} = 0;
    foreach my $workgroup (@$workgroups){
        my $wg = OESS::Workgroup->new(db => $db, workgroup_id => $workgroup->{'workgroup_id'});
        push(@{$user->{'workgroups'}}, $wg);
        if($wg->type() eq 'admin'){
            $user->{'is_admin'} = 1;
        }
    }

    #if they are an admin they are a part of every workgroup
    if($user->{'is_admin'}){
        $user->{'workgroups'} = ();
        my $workgroups = $db->execute_query("select workgroup_id from workgroup",[]);
        
        foreach my $workgroup (@$workgroups){
            push(@{$user->{'workgroups'}}, OESS::Workgroup->new(db => $db, workgroup_id => $workgroup->{'workgroup_id'}));
        }

    }

    return $user;
}

=head2 find_user_by_remote_auth
=cut
sub find_user_by_remote_auth{
    my %params = @_;
    my $db = $params{'db'};
    my $remote_user = $params{'remote_user'};

    my $user_id = $db->execute_query("select remote_auth.user_id from remote_auth where remote_auth.auth_name = ?",[$remote_user]);
    if(!defined($user_id) || !defined($user_id->[0])){
        return;
    }

    return $user_id->[0];
}

1;
