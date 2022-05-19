#!/usr/bin/perl

use strict;
use warnings;

use Log::Log4perl;
use GRNOC::WebService::Method;
use GRNOC::WebService::Dispatcher;

use OESS::AccessController::Default;
use OESS::Config;
use OESS::DB;
use OESS::DB::ACL;
use OESS::DB::User;
use OESS::ACL;
use OESS::RabbitMQ::Client;
use OESS::RabbitMQ::Topic qw(discovery_topic_for_node fwdctl_topic_for_node);
use OESS::Webservice;


my $config = new OESS::Config(config_filename => '/etc/oess/database.xml');
my $db = new OESS::DB(config_obj => $config);
my $ac = new OESS::AccessController::Default(db => $db);
my $ws = new GRNOC::WebService::Dispatcher();


my $create_acl = GRNOC::WebService::Method->new(
	name        => "create_acl",
	description => "Creates an ACL on the specified interface",
	callback    => sub { create_acl( @_ ) }
);
$create_acl->add_input_parameter(
    name        => 'workgroup_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 0,
    description => "Workgroup to which ACL is applied"
); 
$create_acl->add_input_parameter(
    name        => 'entity_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 0,
    description => "Network entity associated with this VLAN range"
);
$create_acl->add_input_parameter(
    name        => 'interface_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => "Interface on which this ACL resides"
);
$create_acl->add_input_parameter(
    name        => 'allow_deny',
    pattern     => $OESS::Webservice::ACL_ALLOW_DENY,
    required    => 1,
    description => "Type of this ACL rule; Is either allow or deny"
);
$create_acl->add_input_parameter(
    name        => 'eval_position',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 0,
    description => "Position in the ACL list where the rule is evaluated. First position is evaluated prior to last position."
);
$create_acl->add_input_parameter(
    name        => 'start',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => "Inclusive start of VLAN range"
);
$create_acl->add_input_parameter(
    name        => 'end',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 0,
    description => "Inclusive end of VLAN range"
);
$create_acl->add_input_parameter(
    name        => 'notes',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => "Any notes or reason for the ACL."
);
$ws->register_method($create_acl);

my $delete_acl = GRNOC::WebService::Method->new(
	name        => "delete_acl",
	description => "Deletes an ACL entry",
	callback    => sub { delete_acl( @_ ) }
);
$delete_acl->add_input_parameter(
    name        => 'interface_acl_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => "The interface acl ID the ACL to be removed."
);
$ws->register_method($delete_acl);

my $edit_acl = GRNOC::WebService::Method->new(
    name        => "edit_acl",
    description => "Edits the specified ACL entry",
    callback    => sub { edit_acl( @_ ) }
);
$edit_acl->add_input_parameter(
    name        => 'allow_deny',
    pattern     => $OESS::Webservice::ACL_ALLOW_DENY,
    required    => 1,
    description => "if the ACL is an allow or deny rule."
);
$edit_acl->add_input_parameter(
    name        => 'entity_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 0,
    description => "the entity the ACL is applied to."
);
$edit_acl->add_input_parameter(
    name       => 'eval_position',
    pattern    => $GRNOC::WebService::Regex::INTEGER,
    required   => 1,
    description=> "the position in the ACL list where the rule will be evaluated."
);
$edit_acl->add_input_parameter(
    name        => 'interface_acl_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => "The interface acl ID of the ACL to be modified."
);
$edit_acl->add_input_parameter(
    name        => 'interface_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 0,
    description => "Unused; kept for backwards compatibility"
);
$edit_acl->add_input_parameter(
    name        => 'notes',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => "Any notes or reason for the ACL."
);
$edit_acl->add_input_parameter(
    name        => 'start',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => "the start vlan tag."
);
$edit_acl->add_input_parameter(
    name        => 'end',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 0,
    description => "the end vlan tag."
);
$edit_acl->add_input_parameter(
    name        => 'workgroup_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 0,
    description => "Workgroup to which ACL is applied"
);
$ws->register_method($edit_acl);

my $get_acl = GRNOC::WebService::Method->new(
    name        => "get_acl",
    description => "get_acl returns the requested ACL entry",
    callback    => sub { get_acl(@_) }
);
$get_acl->add_input_parameter(
    name        => 'interface_acl_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'Id of ACL entry'
);
$ws->register_method($get_acl);

my $get_acls = GRNOC::WebService::Method->new(
    name        => "get_acls",
    description => "get_acls returns a list of all ACL entries on interface_id",
    callback    => sub { get_acls(@_) }
);
$get_acls->add_input_parameter(
    name        => 'interface_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'Id of interface associated with ACL entries'
);
$ws->register_method($get_acls);

my $get_acl_history = GRNOC::WebService::Method->new(
    name        => 'get_acl_history',
    description => 'Gets the creation and edit history of an ACL',
    callback    => sub { get_acl_history( @_ ) }
);
$get_acl_history->add_input_parameter(
    name        => 'interface_acl_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'The interface ACL ID to get its history.'
);
$ws->register_method($get_acl_history);


sub create_acl {
    my $method = shift;
    my $params = shift;

    my $workgroup_id   = $params->{workgroup_id}{value} || -1;
    my $workgroup_name = "All workgroups";
    if ($workgroup_id != -1) {
        $workgroup_name = OESS::DB::Workgroup::fetch(db => $db, workgroup_id => $workgroup_id)->{name};
    }

    my $interface = OESS::DB::Interface::fetch(db => $db, interface_id => $params->{interface_id}{value});

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my ($in_workgroup, $wg_err) = $user->has_workgroup_access(role => 'normal', workgroup_id => $interface->{workgroup_id});
    my ($in_sysadmins, $sy_err) = $user->has_system_access(role => 'normal');
    if (!$in_workgroup && !$in_sysadmins) {
        $method->set_error($wg_err);
        return;
    }

    my $username = $user->usernames()->[0];

    my $interface_name = $interface->{name};
    my $vlan_start = $params->{"start"}{'value'};
    my $vlan_end = $params->{"end"}{'value'};

    my $logger = Log::Log4perl->get_logger("OESS.ACL");
    $logger->debug("Initiating creation of ACL at <time> for $workgroup_name.");    
    
    my $acl = OESS::ACL->new(
        db => $db,
        model => {
            workgroup_id  => $params->{"workgroup_id"}{'value'} || -1,
            interface_id  => $params->{"interface_id"}{'value'},
            allow_deny    => $params->{"allow_deny"}{'value'},
            eval_position => $params->{"eval_position"}{'value'} || undef,
            start         => $vlan_start,
            end           => $vlan_end || undef,
            notes         => $params->{"notes"}{'value'} || undef,
            entity_id     => $params->{"entity_id"}{'value'} || -1,
        }
    );
    my $acl_id = $acl->create($user->user_id, $interface->{workgroup_id});
    if (!$acl_id) {
        $method->set_error("Couldn't create ACL.");
        return;
    }

    $logger->info("Created ACL with id $acl_id at " .localtime(). " for $workgroup_name on $interface_name from vlans $vlan_start to $vlan_end, Action was initiated by $username");
    return { results => [{ success => 1, interface_acl_id => $acl_id }] };
}

sub get_acl {
    my $method = shift;
    my $params = shift;

    my $acl = OESS::DB::ACL::fetch(db => $db, interface_acl_id => $params->{interface_acl_id}{value});
    if (!defined $acl) {
        $method->set_error("Couldn't find requested ACL.");
        return;
    }

    my $interface = OESS::DB::Interface::fetch(db => $db, interface_id => $acl->{interface_id});
    if (!defined $interface) {
        $method->set_error("Couldn't find requted ACL's interface.");
        return;
    }

    # Permissions check
    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($access_ok, $access_err) = $user->has_workgroup_access(
        role => 'read-only',
        workgroup_id => $interface->{workgroup_id}
    );
    if (defined $access_err) {
        $method->set_error($access_err);
        return;
    }

    return { results => [ $acl ] };
}

sub get_acls {
    my $method = shift;
    my $params = shift;

    my $interface = new OESS::Interface(
        db => $db,
        interface_id => $params->{interface_id}{value}
    );

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($access_ok, $access_err) = $user->has_workgroup_access(
        role => 'read-only',
        workgroup_id => $interface->workgroup_id
    );
    if (defined $access_err) {
        $method->set_error($access_err);
        return;
    }

    my $acls = OESS::DB::ACL::fetch_all(
        db => $db,
        interface_id => $params->{interface_id}{value}
    );
    my $result = [];
    foreach my $acl (@$acls) {
        my $obj = new OESS::ACL(db => $db, model => $acl);
        push @$result, $obj->to_hash;
    }
    return { results => $result };
}

sub edit_acl {
    my $method = shift;
    my $params = shift;

    my $acl_id       = $params->{interface_acl_id}{value};
    my $workgroup_id = $params->{workgroup_id}{value};
    my $vlan_start   = $params->{start}{value};
    my $vlan_end     = $params->{end}{value};
    my $logger       = Log::Log4perl->get_logger("OESS.ACL");


    my $original_acl = new OESS::ACL(db => $db, interface_acl_id => $acl_id);
    my $acl = new OESS::ACL(db => $db, interface_acl_id => $acl_id);

    my $interface = new OESS::Interface( db => $db, interface_id => $original_acl->interface_id);

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($in_workgroup, $wg_err) = $user->has_workgroup_access(role => 'normal', workgroup_id => $interface->workgroup_id);
    my ($in_sysadmins, $sy_err) = $user->has_system_access(role => 'normal');
    if (!$in_workgroup && !$in_sysadmins) {
        $method->set_error($wg_err);
        return;
    }

    $db->start_transaction();
    if ($acl->{'eval_position'} != $params->{eval_position}{value}) {

        foreach my $a (@{$interface->acls}) {
            next if $a->{interface_acl_id} == $acl_id;

            if ($params->{eval_position}{value} < $acl->{eval_position}) {

                if ($a->{eval_position} >= $params->{eval_position}{value} && $a->{eval_position} < $acl->{eval_position}) {
                    $a->{eval_position} += 10;
                    if (!$a->update_db) {
                        $method->set_error( $db->get_error() );
                        $db->rollback();
                        return;
                    }
                }

            } elsif( $params->{eval_position}{value} > $acl->{eval_position}){
                if ($a->{eval_position} <= $params->{eval_position}{value} && $a->{eval_position} > $acl->{eval_position}) {
                    $a->{eval_position} -= 10;
                    if(!$a->update_db) {
                        $method->set_error( $db->get_error() );
                        $db->rollback();
                        return;
                    }
                }
            }
        }
    }

    $acl->{workgroup_id}  = $params->{workgroup_id}{value};
    $acl->{entity_id}     = $params->{entity_id}{value};
    $acl->{interface_id}  = $params->{interface_id}{value};
    $acl->{allow_deny}    = $params->{allow_deny}{value};
    $acl->{eval_position} = $params->{eval_position}{value};
    $acl->{start}         = $params->{start}{value};
    $acl->{end}           = $params->{end}{value};
    $acl->{notes}         = $params->{notes}{value};
    my $success = $acl->update_db;

    my $error = OESS::DB::ACL::add_acl_history(
        db => $db,
        event => 'edit',
        acl => $acl,
        user_id => $user->user_id,
        workgroup_id => $interface->workgroup_id,
        state => 'active'
    );
    if (defined $error) {
        warn $error;
    }

    my $original_values =  $original_acl->to_hash();

    my $original_workgroup_name;
    if ($original_acl->{workgroup_id}) {
        $original_workgroup_name = OESS::DB::Workgroup::fetch(db => $db, workgroup_id => $original_acl->{workgroup_id})->{name};
    } else{
        $original_workgroup_name = "All workgroups";
    }

    my $workgroup_name;
    if ($workgroup_id && $workgroup_id != -1){
        $workgroup_name = OESS::DB::Workgroup::fetch(db => $db, workgroup_id => $acl->{workgroup_id})->{'name'};
    } else{
        $workgroup_name = "All workgroups";
    }

    my $original_interface_name = OESS::DB::Interface::fetch(db => $db, interface_id => $original_acl->{interface_id})->{name};
    my $interface_name = OESS::DB::Interface::fetch(db => $db, interface_id => $acl->{interface_id})->{'name'};

    if (!defined $success) {
        $logger->info("Failed to update acl with id $acl_id, at ". localtime() . " on $interface_name. Action was initiated by " . $user->usernames()->[0] . ".");
        $method->set_error( $db->get_error() );
	    $db->rollback();
        return;
    }

    $db->commit();

    my $output_string = "Changed: ";
    if ($original_acl->{start} != $acl->{start}) {
        $output_string .= "vlan start from $original_acl->{start} to $acl->{start}";
    }
    if ($original_acl->{end} != $acl->{end}) {
        $output_string .= " vlan end from $original_acl->{end} to $acl->{end}";
    }
    if ($original_acl->{allow_deny} ne $acl->{allow_deny}) {
        $output_string .= " permission from $original_acl->{allow_deny} to $acl->{allow_deny}";
    }
    if ($original_acl->{workgroup_id} != $acl->{workgroup_id}) {
        $output_string .= " workgroup from $original_acl->{workgroup_id} to $acl->{workgroup_id}";
    }

    $logger->info("Updated ACL with id $acl_id, at ". localtime() ." on $interface_name. Action was initiated by " . $user->usernames()->[0] . ".");
    $logger->info($output_string);

    return { results => [{ success => 1 }] };
}

sub delete_acl {
    my $method = shift;
    my $params = shift;

    my $logger = Log::Log4perl->get_logger("OESS.ACL");
    my $interface_acl_id   = $params->{'interface_acl_id'}{'value'};

    my $acl = new OESS::ACL(db => $db, interface_acl_id => $interface_acl_id);

    my $request_workgroup = OESS::DB::Interface::fetch(db => $db, interface_id => $acl->interface_id)->{workgroup_id};

    my ($user, $err) = $ac->get_user(username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my ($in_workgroup, $wg_err) = $user->has_workgroup_access(role => 'normal', workgroup_id => $request_workgroup);
    my ($in_sysadmins, $sy_err) = $user->has_system_access(role => 'normal');
    if (!$in_workgroup && !$in_sysadmins) {
        $method->set_error($wg_err);
        return;
    }
    my $username = $user->usernames()->[0];

    $db->start_transaction;
    my $history_error = OESS::DB::ACL::add_acl_history(
        db => $db,
        event => 'decom',
        acl => $acl,
        user_id => $user->user_id,
        workgroup_id => $request_workgroup,
        state => 'decom'
    );
    if (defined $history_error) {
        $db->rollback;
	    $method->set_error($history_error);
        return;
    }

    my ($result, $error) = OESS::DB::ACL::remove(
        db => $db,
        interface_acl_id => $interface_acl_id
    );
    if (defined $error) {
        $logger->info("Failed to delete ACL with id $interface_acl_id at ". localtime() ." Action was initiated by $username.");
        $db->rollback;
	    $method->set_error($error);
        return;
    }
    $db->commit;

    $logger->info("Deleted ACL with id $interface_acl_id at ". localtime() . " Action was initiated by $username.");
    return { results => [{ success => 1 }] };
}

sub get_acl_history {
    my ( $method, $args ) = @_ ;
    my $logger = Log::Log4perl->get_logger("OESS.ACL");

    my $user = new OESS::User(db => $db, username => $ENV{REMOTE_USER});
    if (!defined $user) {
        $method->set_error("User '$ENV{REMOTE_USER}' is invalid.");
        return;
    }

    my $acl = new OESS::ACL(db => $db, interface_acl_id => $args->{interface_acl_id}{value});
    if (!defined $acl) {
        $method->set_error("Failed to get acl for acl history");
        return;
    }

    my $interface = new OESS::Interface(db => $db, interface_id => $acl->{interface_id});
    if (!defined $interface) {
        $method->set_error("Failed to get interface for acl history with interface id $acl->{interface_id}");
        return;
    }

    my ($in_workgroup, $wg_err) = $user->has_workgroup_access(role => 'read-only', workgroup_id => $interface->{workgroup_id});
    my ($in_sysadmins, $sy_err) = $user->has_system_access(role => 'read-only');
    if (!$in_workgroup && !$in_sysadmins) {
        $method->set_error($wg_err);
        return;
    }

    my $events = OESS::DB::ACL::get_acl_history(
        db                  => $db,
        interface_acl_id    => $args->{interface_acl_id}{value},
        workgroup_id        => $args->{workgroup_id}{value}
    );
    if ( !defined $events ) {
        $logger->info("Failed to get interface ACL history with id $args->{interface_acl_id}{value} at ". localtime() ." Action was initiated by $ENV{REMOTE_USER}.");
        $method->set_error( $db->get_error() );
        return;
    }

    my $results->{'results'} = $events;
    return $results;
}

$ws->handle_request;
