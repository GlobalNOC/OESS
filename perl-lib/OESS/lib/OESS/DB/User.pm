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
    my $username = $params{'username'};

    my $user;

    if (defined $user_id) {
        my $q = "
            select remote_auth.auth_name as username, user.*
            from user
            join remote_auth on remote_auth.user_id=user.user_id
            where user.user_id = ?
        ";
        $user = $db->execute_query($q, [$user_id]);
    } else {
        my $q = "
            select remote_auth.auth_name as username, user.*
            from user
            join remote_auth on remote_auth.user_id=user.user_id
            where remote_auth.auth_name = ?
        ";
        $user = $db->execute_query($q, [$username]);
    }
    if (!defined($user) || !defined($user->[0])){
        return;
    }

    my $admin_query = "
        select exists(
            select type
            from workgroup
            join user_workgroup_membership on workgroup.workgroup_id=user_workgroup_membership.workgroup_id
            where user_workgroup_membership.user_id=? and type='admin'
        ) as is_admin;
    ";
    my $admin_result = $db->execute_query(
        $admin_query,
        [$user->[0]->{user_id}]
    );
    if (!defined($admin_result) || !defined($admin_result->[0])){
        return;
    }

    # Replace is_admin field with scan for admin workgroups
    $user->[0]->{is_admin} = $admin_result->[0]->{is_admin};

    return $user->[0];
}

=head2 get_workgroups

=cut
sub get_workgroups {
    my $args = {
        db       => undef,
        user_id  => undef,
        @_
    };

    my $is_admin_query = "
        SELECT workgroup.*
        FROM workgroup
        JOIN user_workgroup_membership ON workgroup.workgroup_id=user_workgroup_membership.workgroup_id AND workgroup.type='admin'
        WHERE user_workgroup_membership.user_id=?
    ";
    my $is_admin = $args->{db}->execute_query($is_admin_query, [$args->{user_id}]);

    my $query;
    my $values;
    if (defined $is_admin && defined $is_admin->[0]) {
        $query = "SELECT * from workgroup ORDER BY workgroup.name ASC";
        $values = [];
    } else {
        $query = "
            SELECT workgroup.*
            FROM workgroup
            JOIN user_workgroup_membership ON workgroup.workgroup_id=user_workgroup_membership.workgroup_id
            WHERE user_workgroup_membership.user_id=?
            ORDER BY workgroup.name ASC
        ";
        $values = [$args->{user_id}];
    }

    my $datas = $args->{db}->execute_query($query, $values);
    if (!defined $datas) {
        return (undef, $args->{db}->get_error);
    }

    return ($datas, undef);
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
