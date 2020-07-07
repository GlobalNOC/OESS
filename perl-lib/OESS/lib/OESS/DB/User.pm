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
                                                  auth_names => $auth_names);

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

   return (undef, 'Required argument `db` is missing.') if !defined $db;
   return (undef, 'Required argument `given_name` is missing.') if !defined $given_name;
   return (undef, 'Required argument `family_name` is missing.') if !defined $family_name;
   return (undef, 'Required argument `email` is missing.') if !defined $email;
   return (undef, 'Required argument `auth_names` is missing.') if !defined $auth_names;
   
   if ($given_name =~ /^system$/ || $family_name =~ /^system$/) {
       return (undef, "Cannot use system as a username.");
   }

   my $query = "INSERT INTO user (email, given_names, family_name, status) VALUES (?, ?, ?, 'active')";
   my $user_id = $db->execute_query($query,[$email,$given_name,$family_name]);

   if (!defined $user_id) {
       return (undef, "Unable to create new user.");
   }

   if (ref($auth_names) eq 'ARRAY') {
       foreach my $name (@$auth_names){
           if (length($name) >=1) {
               $query = "INSERT INTO remote_auth (auth_name, user_id) VALUES (?, ?)";
               $db->execute_query($query, [$name,$user_id]); 
           }
       }
   } else {
       if (length($auth_names) >=1) {
           $query = "INSERT INTO remote_auth (auth_name, user_id) VALUES (?, ?)";
           $db->execute_query($query, [$auth_names, $user_id]);
       } else {
           return (undef, "Username should be at least 1 character long");
       }
   }

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
    my %params = @_; 
    my $db = $params{db};
    my $user_id = $params{user_id};

    return (undef, 'Required argument `db` is missing.') if !defined $db;
    return (undef, 'Requried argument `user_id` is missing.') if !defined $user_id;

    my $info = OESS::DB::User::fetch(db => $db, user_id => $user_id);

    if (!defined $info) {
        return (undef, "Internal error identifying user with id: $user_id");
    }

    if ($info->{'given_names'} =~ /^system$/i || $info->{'family_name'} =~ /^system$/i) {
       return (undef, "Cannot delete the system user.");
    }


    if (!defined $db->execute_query("DELETE FROM user_workgroup_membership WHERE user_id = ?", [$user_id])) {
        return (undef, "Internal error delete user.");
    }
    if (!defined $db->execute_query("DELETE FROM remote_auth WHERE user_id = ?", [$user_id])) {
        return (undef, "Internal error delete user.");
    }
    if (!defined $db->execute_query("DELETE FROM user WHERE user_id =?", [$user_id])) {
        return (undef, "Internal error delete user.");
    }


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
    my $db = $params{'db'};
    
    my $user_id      = $params{'user_id'};
    my $given_name   = $params{'given_name'};
    my $family_name  = $params{'family_name'};
    my $email        = $params{'email'};
    my $auth_names   = $params{'auth_names'};
    my $status       = $params{'status'};

    return (undef, 'Required argument `db` is missing.') if !defined $db;
    return (undef, 'Required arguemnt `user_id` is missing.') if !defined $user_id; 
    return (undef, 'Required argument `given_name` is missing.') if !defined $given_name;
    return (undef, 'Required argument `family_name` is missing.') if !defined $family_name;
    return (undef, 'Required argument `email` is missing.') if !defined $email;
    return (undef, 'Required argument `auth_names` is missing.') if !defined $auth_names;
    return (undef, 'Required argument `status` is missing.') if !defined $status;
     
    if ($given_name =~ /^system$/ || $family_name =~ /^system$/) {
        return(undef, "User 'system' is reserved.");
    }


    my $query = "UPDATE user SET email = ?, given_names = ?, family_name = ?, status = ? WHERE user_id = $user_id";

    my $results = $db->execute_query($query, [$email, $given_name, $family_name, $status]);

    if (!defined $user_id || $results == 0) {
        return (undef, "Unable to edit user - does this user actually exist?");
    }

    $db->execute_query("DELETE FROM remote_auth WHERE user_id = ?", [$user_id]);

    if (ref($auth_names) eq 'ARRAY') {
        foreach my $name (@$auth_names){
            if (length $name >=1) {
                $query = "INSERT INTO remote_auth (auth_name, user_id) VALUES (?, ?)";
                $db->execute_query($query, [$name,$user_id]);
            }
        }
     } else {
         return (undef, 'Auth_Names is required to be at least 1 character.') if length $auth_names <1;
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
    my $datas;
    if (defined $is_admin && defined $is_admin->[0]) {
        $query = "SELECT * from workgroup ORDER BY workgroup.name ASC";
        $values = [];
        $datas = $args->{db}->execute_query($query);
    } else {
        $query = "
            SELECT workgroup.*
            FROM workgroup
            JOIN user_workgroup_membership ON workgroup.workgroup_id=user_workgroup_membership.workgroup_id
            WHERE user_workgroup_membership.user_id=?
            ORDER BY workgroup.name ASC
        ";
        $values = [$args->{user_id}];
        $datas = $args->{db}->execute_query($query,$values);
    }

    if (!defined $datas) {
        return (undef, $args->{db}->get_error);
    }
    if (!defined $datas->[0]){
        return (undef, "Returned 0 Workgroups");
    }
    my $length = @$datas;
    return ($datas, $length);
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
=head2 has_system_access

=item db
    Denotes the database we are checking for access
=back

=item user_id
    Denotes the user_id of the user whose access we are checking
=back

=item username
    Denotes the username of the user whose access we are checking
=back

=item workgroup_id
   Denotes the workgroup_id of the workgroup we checking the users permissions in
=back

=item role
   Denotes the level of access the user needs for a particular action
=back

    my $results = OESS::DB::User::has_system_access(
                                  db           => $db,
                                  user_id      => $user_id,
                                  role        => $role);
    
    OR

    my $results = OESS::DB::User::has_workgroup_access(
                                  db           => $db,
                                  username     => $username,,
                                  role        => $role);
 
has_system_access checks if the user belongs to and admin C<workgroup> and then
checks if their C<role> is the same or higher level than the passed C<role>. If
it is then the User has the proper level of permissions based on the following
C<admin> highest access C<normal> medium access C<read-only> mimum access
Then the function grants permission Otherwise spits out an error.
=cut
sub has_system_access{
    my %params = @_;
    my $db = $params{'db'};
    my $user_id = $params{'user_id'};
    my $username = $params{'username'};
    my $role = $params{'role'};


    return {error => "Required argument 'db' is missing."} if !defined $db;
    return {error => "Required to pass either 'user_id' or 'username'."} if !defined $user_id && !defined $username;
    return {error => "Required argument 'role' is missing."} if !defined $role;
    my $user;
    if (!defined $user_id) {
        $user = OESS::DB::User::fetch(db => $db, username => $username);
    } else {
        $user = OESS::DB::User::fetch(db => $db, user_id =>$user_id);
    }
    
    if (!defined $user || $user->{'status'} eq 'decom'){
        return {error => "Invalid or decommissioned user specified."};
    }
    if ($user->{'is_admin'} == 1) {
        my ($workgroups, $wg_err) = OESS::DB::User::get_workgroups(db => $db, user_id => $user->{user_id});
        if (!defined $workgroups){
                return {error => $workgroups->[2]->{type}};
        }
        my $read_access = 1;
        my $normal_access = 0;
        my $admin_access = 0;
        
        foreach my $workgroup (@$workgroups){
          if ( $workgroup->{type} ne 'admin'){
              next;
          }
          my $role_result = $db->execute_query("SELECT role FROM user_workgroup_membership WHERE user_id = ? AND workgroup_id = ?",
                                                      [$user->{user_id}, $workgroup->{'workgroup_id'}]);
          my $group_role = $role_result->[0]->{role};
          
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
=head2 has_workgroup_access

=item db
    Denotes the database we are checking for access
=back

=item user_id
    Denotes the user_id of the user whose access we are checking
=back

=item username
    Denotes the username of the user whose access we are checking
=back

=item workgroup_id
   Denotes the workgroup_id of the workgroup we checking the users permissions in
=back

=item role
   Denotes the level of access the user needs for a particular action
=back

    my $results = OESS::DB::User::has_workgroup_access(
                                  db           => $db,
                                  user_id      => $user_id,
                                  workgroup_id => $workgroup_id,
                                  $role        => $role);
    
    OR

    my $results = OESS::DB::User::has_workgroup_access(
                                  db           => $db,
                                  user_id      => $user_id,
                                  workgroup_id => $workgroup_id,
                                  $role        => $role);

has_workgroup_access checks if a specified user's C<role> found in C<user_workgroup_membership>
identified by the C<workgroup_id> and C<user_id> or C<username> matches the passed
C<role> and grants access based on that criteria. The roles are ranked as follows
C<admin> highest access, C<normal> middle access, C<read-only> minimum access. 
It will also grant access to system admins of an appropriate level.

=cut
sub has_workgroup_access {
    my %params = @_;
    my $db = $params{'db'};
    my $user_id = $params{'user_id'};
    my $username = $params{'username'};
    my $workgroup_id = $params{'workgroup_id'};
    my $role = $params{'role'};

    return {error => "Required argument 'db' is missing."} if !defined $db;
    return {error => "Required to pass either 'user_id' or 'username'."} if !defined $user_id && !defined $username;
    return {error => "Required argument 'workgroup_id' is missing."} if !defined $workgroup_id;
    return {error => "Required argument 'role' is missing."} if !defined $role;
    my $user;
    if (!defined $user_id) {
        $user = OESS::DB::User::fetch(db => $db, username => $username);
    } else {
        $user = OESS::DB::User::fetch(db => $db, user_id => $user_id);
    }
    
    if (!defined $user || $user->{'status'} eq 'decom') {
        return { error => "Invalid or decommissioned user specified." };
    }
    
    my $workgroup = OESS::DB::Workgroup::fetch(db => $db, workgroup_id => $workgroup_id);

    if (!defined $workgroup || $workgroup->{'status'} eq 'decom') {
        return { error => "Invalid or decommissioned workgroup specified." };
    }
    if ($workgroup->{'type'} eq 'admin') {
        my $high_admin = has_system_access(db => $db, user_id => $user->{user_id}, role => $role);
        if (!defined $high_admin) {
            return;
        } else {
            return { error => $high_admin->{'error'}};
        }
    } else {
       my $user_wg_role = $db->execute_query("SELECT role from user_workgroup_membership WHERE user_id = ? and workgroup_id = ?",
                                             [$user->{user_id}, $workgroup_id])->[0]->{'role'};
       my $read_access = 0;
       my $normal_access = 0;
       my $admin_access = 0;
       if(defined $user_wg_role) {
           $read_access = 1;
           if ($user_wg_role eq 'normal') {
               $normal_access = 1;
           }
           if ($user_wg_role eq 'admin') {
               $normal_access = 1;
               $admin_access = 1;        
           }
       }
       my $is_sys_admin;
       if ($role eq 'read-only') {
           $is_sys_admin = has_system_access(db =>$db, user_id => $user->{user_id}, role => 'read_only');
       } else {
           $is_sys_admin = has_system_access(db => $db, user_id => $user->{user_id}, role => 'normal');
       }
       if (!defined $is_sys_admin) {
           $read_access = 1;
           $normal_access = 1;
           $admin_access = 1;
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
