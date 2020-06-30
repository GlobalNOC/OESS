#!/usr/bin/perl         

use strict;
use warnings;

use OESS::Workgroup;
use OESS::DB::Workgroup;
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
=head2 add_user

=item db
    Used to denote which database is being used for the transactions
=back

=item given_name
    Denotes the first name of the user to be added to the database
=back

=item family_name
    Denotes the last name of the user to be added to the database
=back

=item email
    Denotes the email address of the user to be added to the database
=back

=item auth_names
    Denotes either a single or list of usernames accreditted to the user
=back

=item status
    Denotes the current status of the account either {'active','decom'};
=back

    my ($result, $err) = OESS::DB::User::add_user(db => $db, 
                                                  given_name => $given_name,
                                                  family_name => $family_name,
                                                  email => $email,
                                                  auth_names => $auth_names,
                                                  status => $status);

Takes the your input and creates the user object in the database and the associated auth_user associated table.


Returns a tuple of of a the result that is the new user id and and error if defined.
=cut
sub add_user {
   my %params = @_;
   my $db = $params{'db'};
   my $given_name = $params{'given_name'};
   my $family_name = $params{'family_name'};
   my $email = $params{'email'};
   my $auth_names = $params{'auth_names'};
   my $status = $args{'status'};

   if (!defined $status) {
       $status = 'active';
   }

   if(!defined $given_name || !defined $family_name || !defined $email || !defined $auth_names) {
      return (undef, "Invalid parameters to add user, please provide a given name, family name, email, and auth names"); 
  }
   
   if ($given_name =~ /^system$/ || $family_name =~ /^system$/) {
       return (undef, "Cannot use system as a username.");
   }
   
   $db->start_transaction();

   my $query = "INSERT INTO user (email, given_names, family_name, status) VALUES (?, ?, ?, ?)";
   my $user_id = $db->execute_query($query,[$email,$given_name,$family_name,$status]);

   if (!defined $user_id) {
       $db->rollback();
       return (undef, "Unable to create new user.");
   }

   if (ref($auth_names) eq 'ARRAY') {
       foreach my $name in (@$auth_names){
           $query = "INSERT INTO remote_auth (auth_name, user_id) VALUES (?, ?)";
           $db->execute_query($query, [$name,$user_id]);
       }
   } else {
       $query = "INSERT INTO remote_auth (auth_name, user_id) VALUES (?, ?)";
       $db->execute_query($query, [$auth_names, $user_id]);
   }
   $db->commit();

   return ($user_id, undef);
}
=head2 delete_user

=item db
    Denotes the database that the user is being deleted from
=back

=item user_id
    Denotes the user_id of the user to be deleted.
=back
    my ($result, $error) = OESS::DB::User::delete_user(db => $db,
                                                       user_id => $user_id);
    Takes you input and delete the associate user from the database and associated tables. (user, user_workgroup_management, auth_names)

Returns a tuple of a result code 1 if correct, and and error
=cut
sub delete_user {
    my $self = shift;
    my %params = @_;
    my $db = $params{'db'};
    my $user_id = $params{'user_id'};

    my $info = $self->fetch(db => $db, user_id => $user_id);

    if (!defined $info) {
        return (undef, "Internal error identifying user with id: $user_id");
    }

    if ($info->[0]->{'given_names'} =~ /^system$/i || $info->[0]->{'family_name'} =~ /^system$/i) {
       return (undef, "Cannot delete the system user.");
    }

    $db->start_transaction();

    if (!defined $db->execute_query("DELETE FROM user_workgroup_membership WHERE user_id = ?", [$user_id])) {
        $db->rollback();
        return (undef, "Internal error delete user.");
    }
    if (!defined $db->execute_query("DELETE FROM remote_auth WHERE user_id = ?", [$user_id])) {
        $db->rollback();
        return (undef, "Internal error delete user.");
    }
    if (!defined $db->execute_query("DELETE FROM user WHERE user_id =?", [$user_id])) {
        $db->rollback();
        return (undef, "Internal error delete user.");
    }

    $db->commit();

    return (1, undef);
}
=head2 edit_user

=item db
    Denotes the database that is being used for these edits that are being made.
=back

=item user_id
    Denotes the user_id of the user who is being editted.
=back

=item given_name
    Denotes the new first name of the edited user
=back

=item family_name
    Denotes the new last name of the edited user
=back

=item email
    Denotes the new email of the edited user
=back

=item auth_names
    Denotes the new usernames of the edited user
=back

=item status
    Denotes the new status of the edited user
=back
    my ($result, $error) = OESS::DB::User::edit_user(db => $db,
                                                      given_name => $given_name,
                                                      family_name => $family_name,
                                                      email => $email,
                                                      auth_names => $auth_names,
                                                      status => $status);
    
    Returns the result of 1 if edit is succesful and an error is neccessary 
=cut
sub edit_user {
    my %params = @_;
    my $db = %params{'db'};
    
    my $user_id      = $params{'user_id'};
    my $given_name   = $params{'given_name'};
    my $family_name  = $params{'family_name'};
    my $email        = $params{'email'};
    my $auth_names   = $params{'auth_names'};
    my $status       = $params{'status'};

    if(!defined $given_name || !defined $family_name || !defined $email || !defined $auth_names) {
       return (undef, "Invalid parameters to edit user, please provide a given name, family name, email, and auth names"); 
    } 
    
    if ($given_name =~ /^system$/ || $family_name =~ /^system$/) {
        return(undef, "User 'system' is reserved.");
    }

    $db->start_transaction();

    my $query = "UPDATE user SET email = ?, given_names = ?, family_name = ?, status = ?, WHERE user_id = ?";

    my $results = $db->execute_query($query, [$email, $given_name, $family_name, $status, $user_id]);

    if (!defined $user_id || $result == 0) {
        $db->rollback();
        return (undef, "Unable to edit user - does this user actually exist?");
    }

    $db->execute_query("DELETE FROM remote_auth WHERE user_id = ?", [$user_id]);

    if (ref($auth_names) eq 'ARRAY') {
        foreach my $name in (@$auth_names){
            $query = "INSERT INTO remote_auth (auth_name, user_id) VALUES (?, ?)";
            $db->execute_query($query, [$name,$user_id]);
        }
     } else {
         $query = "INSERT INTO remote_auth (auth_name, user_id) VALUES (?, ?)";
         $db->execute_query($query, [$auth_names, $user_id]);
     }
     $db->commit();

     return (1,undef)
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
=head2 authorization_system
=cut
sub authorization_system{
    my $self = shift;
    my %params = @_;
    my $db = $params{'db'};
    my $user_id = $params{'user_id'};
    my $username = $params{'username'};
    my $role = $params{'role'};

    if (!defined $user_id) {
        $user_id = $self->find_user_by_remote_auth(db => $db, remote_user => $username);
        if (!defined $user_id) {
            return {error => "Invalid or decommissioned user specified."};
        }
    }
    my $user = $self->fetch(db => $db, user_id => $user_id);
    
    if (!defined $user || $user->{'status'} eq 'decom'){
        return {error => "Invalid or decommissioned user specified."};
    }
    if ($user->{'is_admin'} == 1) {
        my $workgroups = $self->get_workgroups(db => $db, user_id => $user_id);
        my $read_access = 1;
        my $normal_access = 0;
        my $admin_access = 0;
        foreach my $workgroup (@$workgroups){
          if ( $workgroup->{'type'} ne 'admin'){
             next;
          }
          my $group_role = $db->execute_query("SELECT role FROM user_workgroup_membership WHERE user_id = ? AND workgroup_id = ?",
                                              [$user_id, $workgroup->{'workgroup_id'}])[0]->{'role'};
          if ($group_role eq 'normal') {
              $normal_access = 1;
          }
          if ($group_role eq 'admin') {
              $normal_access = 1;
              $admin_access = 1;
          }
        }
        if ($role eq 'read-only' && $read_access == 1) {
           return;
        } elsif ($role eq 'normal' && $normal_access == 1) {
           return;
        } elsif ($role eq 'admin' && $admin_access ==1)  {
           return;
        } else {
           return { error => "User $user->{'username'} does not have the proper level of access." };
        }
    } else {
       return {error => "User $user->{'username'} does not have system admin privileges."};
    }
}
=head2 authorization_workgroup
=cut
sub authorization_workgroup{
    my $self = shift;
    my %params = @_;
    my $db = $params{'db'};
    my $user_id = $params{'user_id'};
    my $username = $params{'username'};
    my $workgroup_id = $params{'workgroup_id'};
    my $role = $param{'role'};

    if (!defined $user_id) {
        $user_id = $self->find_user_by_remoate_auth(db => $db, remove_user => $username);
        if (!defined $user_id) {
            return { error => "Invalid or decommissioned user specified." };
        }
    }
    my $user = $self->fetch(db => $db, user_id = $user_id);
    
    if (!defined $user || $user->{'status'} eq 'decom') {
        return { error => "Invalid or decommissioned user specified." };
    }
    
    my $workgroup = OESS::DB::Workgroup::fetch(db => $db, workgroup_id => $workgroup_id);

    if (!defined $workgroup || $workgroup->{'status'} eq 'decom') {
        return { error => "Invalid or decommissioned workgroup specified." };
    }
    if ($workgroup->{'type'} eq 'admin') {
        my $high_admin = $self->authorization_system(db => $db, user_id => $user_id, role => $role);
        if (!defined $high_admin) {
            return;
        } else {
            return { error => $high_admin->{'error'}};
        }
    } else {
       my $user_wg_role = $db->execute_query("SELECT role from user_workgroup_membership WHERE user_id = ? and workgroup_id = ?",
                                             [$user_id, $workgroup_id])[0]->{'role'};
       my $read_access = 1;
       my $normal_access = 0;
       my $admin_access = 0;
       if ($user_wg_role eq 'normal') {
           $normal_access = 1;
       }
       if ($user_wg_role eq 'admin') {
           $normal_access = 1;
           $admin_access = 1;        
       }
       my $is_sys_admin;
       if ($role eq 'read-only') {
           $is_sys_admin = $self->authorization_system(db =>$db, user_id => $user_id, role => 'read_only');
       } else {
           $is_sys_admin = $self->authorization_system(db => $db, user_id => $user_id, role => 'normal');
       }
       if (!defined $is_sys_admin) {
           $normal_user = 1;
           $admin_user = 1;
       }
        if ($role eq 'read-only' && $read_access == 1) {
            return;
        } elsif ($role eq 'normal' && $normal_access == 1) {
            return;
        } elsif ($role eq 'admin' && $admin_access == 1) {
            return;
        } else {
            return {error => "User $user->{'username'} does not have the proper access permissions"};
            
        }
    }
}
1;
