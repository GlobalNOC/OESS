use strict;
use warnings;

package OESS::Notification;

use URI::Escape;
use OESS::Database;
use GRNOC::Config;
use GRNOC::WebService::Client;
use Data::Dumper;
use MIME::Lite;
use Template;

use Net::DBus::Exporter qw (org.nddi.notification);
use Net::DBus qw(:typing);

use base qw(Net::DBus::Object);

#--------------------------------------------------------------------

#----- OESS::Notification

#-----

#----- Copyright(C) 2012 The Trustees of Indiana University

#--------------------------------------------------------------------

#----- $HeadURL: $

#----- $Id: $

#-----

#----- Object handles Notification Functions required for OE-SS.

#---------------------------------------------------------------------

=head1 NAME

OESS::Notification  

=head1 VERSION:

GRNOC:OESS::Notification 1.0.0

=cut

our $VERSION = '1.0.0';

=head1 SYNOPSIS

=cut

=head2 C<new()>



=cut

sub new {
    my $that  = shift;
    my $class = ref($that) || $that;
    #my $service = shift;
    my %args  = @_;
    my $service = $args{'service'};
    #my $self  = \%args;
    
    my $self = $class->SUPER::new($args{'service'}, "/controller1" );
    $self->{'config_file'} = $args{'config_file'};
    return if !defined( $self->{'config_file'} );

    bless $self, $class;

    $self->_process_config_file();
    $self->_connect_services();
    $self->_build_templates();

    dbus_signal("signal_circuit_provision", [["dict","string",["variant"]]],['string']);
	dbus_signal("signal_circuit_modify", [["dict","string",["variant"]]]);
	dbus_signal("signal_circuit_decommission",  [["dict","string",["variant"]]],['string']);
    dbus_signal("signal_circuit_failover",  [["dict","string",["variant"]]],['string']);

	dbus_method("circuit_provision", [["dict","string",["variant"]]],['string']);
	dbus_method("circuit_modify", [["dict","string",["variant"]]],['string']);
	dbus_method("circuit_decommission",  [["dict","string",["variant"]]],['string']);
    dbus_method("circuit_failover",  [["dict","string",["variant"]]],['string']);


    return $self;
}

sub circuit_provision {
	my $self = shift;
	my $circuit = shift;


    my $circuit_notification_data = $self->get_notification_data(  circuit =>$circuit );   
    #$circuit->{'clr'} = $circuit_notification_data->{'clr'}; 
   
        $self->send_notification(
                                 to => $circuit_notification_data->{'affected_users'},
                                 notification_type =>'provision',
                                 workgroup => $circuit_notification_data->{'workgroup'},
                                 circuit_data => $circuit_notification_data->{'circuit'},
                                 forced_by => $circuit->{'forced_by'}
                                );

	$self->emit_signal("signal_circuit_provision", $circuit);

}


sub circuit_modify {
	my $self = shift;
	my $circuit = shift;

	warn ("in circuit modify");

     my $circuit_notification_data = $self->get_notification_data( circuit => $circuit );   
    #$circuit
    #$circuit->{'clr'} = $circuit_notification_data->{'clr'};
    #foreach my $user ( @{$circuit_notification_data->{'affected_users'} } ){
    
        

    $self->send_notification( 
                             to => $circuit_notification_data->{'affected_users'},
                             notification_type =>'modify',
                             workgroup => $circuit_notification_data->{'workgroup'},
                             circuit_data => $circuit_notification_data->{'circuit'}                                          
                            );
    

	$self->emit_signal("signal_circuit_modify", $circuit);

}
    

sub circuit_decommission {
	my $self = shift;
	my $circuit = shift;

    my $circuit_notification_data = $self->get_notification_data(  circuit =>$circuit );      

    $self->send_notification(
                             to => $circuit_notification_data->{'affected_users'},
                             notification_type =>'decommission',
                             workgroup => $circuit_notification_data->{'workgroup'},
                             circuit_data => $circuit_notification_data->{'circuit'}
                             
                            );

    #in case anything needs to listen to this event
	$self->emit_signal("signal_circuit_decommission", $circuit);

}

#dbusmethod circuit_failover

sub circuit_failover {
	my $self = shift;
	my ($circuit) = @_;
    
    my $circuit_notification_data = $self->get_notification_data(  circuit =>$circuit );

     my $notification_type = "failover_".$circuit->{'failover_type'};
    if ($circuit->{'failover_type'}='forced' && $circuit->{'forced_by'}) {
        $notification_type = "failover_forced";
    }
    
    $self->send_notification(
                             to => $circuit_notification_data->{'affected_users'},
                             notification_type => $notification_type,
                             workgroup => $circuit_notification_data->{'workgroup'},
                             circuit_data => $circuit_notification_data->{'circuit'},
                             forced_by => $circuit->{'forced_by'}
                            );

    #in case anything needs to listen to this event
	$self->emit_signal("signal_circuit_failover", $circuit);

}



sub send_notification {
    my $self= shift;
    
    my %args = (
                notification_type => undef,
                circuit_data => undef,
                #contact_data => undef,
                to => [],
                @_
               );
    my @to_list= ();
    
    
    my $subject_map = {                       
                       'modify' => "OESS Notification: Circuit ".$args{'circuit_data'}{'description'}." Modified",
                       'provision' => "OESS Notification: Circuit ".$args{'circuit_data'}{'description'}." Provisioned",
                       'decommission' => "OESS Notification: Circuit ".$args{'circuit_data'}{'description'}." Decommissioned",
                       
                       'failover_failed_unknown' => "OESS Notification: Circuit ".$args{'circuit_data'}{'description'}." is down",
                       'failover_failed_no_backup' =>"OESS Notification: Circuit ".$args{'circuit_data'}{'description'}." is down",
                       'failover_failed_path_down' => "OESS Notification: Circuit ".$args{'circuit_data'}{'description'}." is down",
                       'failover_success' => "OESS Notification: Circuit ".$args{'circuit_data'}{'description'}." Successful Failover to alternate path",
                       'failover_manual_success' => "OESS Notification: Circuit ".$args{'circuit_data'}{'description'}." Successful Failover to alternate path",
                       'failover_forced' => "OESS Notification: Circuit ".$args{'circuit_data'}{'description'}." Manual Failover to down path",
                      };
    
    my $vars = {
                workgroup => $args{'workgroup'},
                circuit_description => $args{'circuit_data'}{'description'},
                clr => $args{'circuit_data'}{'clr'},
                from_signature_name => $self->{'from_name'},
                
               };
    
    my $body;
    my $template = $args{'notification_type'} . '_template';
    
    $self->{'tt'}->process(\$self->{$template}, $vars, \$body);
    
    foreach my $user (@{$args{'to'}} ){
        push (@to_list, $user->{'email_address'} );
    }
    my $to_string = join(",", @to_list );

    $self->_send_notification(  to => $to_string,
                                 body => $body,
                                 subject => $subject_map->{ $args{'notification_type'} }, 
                                
                                );
    return 1;
}


sub _build_templates {

    my $self = shift;

    $self->{'tt'} = Template->new();

    $self->{'provision_template'} = <<TEMPLATE;

Greetings [%given_name%] [%last_name%],

The following circuit has been provisioned: 

[%clr%]

Sincerely,

[%from_signature_name%]

TEMPLATE

$self->{'decommission_template'} = <<TEMPLATE;

Greetings [%given_name%] [%last_name%],

The circuit [%circuit_description%] has been decommissioned. For reference, its layout record is below:

[%clr%]

Sincerely,

[%from_signature_name%]

TEMPLATE


$self->{'modify_template'} = <<TEMPLATE;

Greetings workgroup: [%workgroup%] ,

The following circuit has been modified:

[%clr%]

Sincerely,

[%from_signature_name%]

TEMPLATE

$self->{'failover_success_template'} = <<TEMPLATE;

Greetings [%given_name%] [%last_name%],

The following circuit has successfully failed over to an alternate path, for reference it is now configured as:

[%clr%]

Sincerely,

[%from_signature_name%]

TEMPLATE

$self->{'failover_manual_success_template'} = <<TEMPLATE;

Greetings [%given_name%] [%last_name%],

The following circuit has successfully failed over to an alternate path, for reference it is now configured as:

[%clr%]

Sincerely,

[%from_signature_name%]

TEMPLATE

$self->{'failover_forced_template'} = <<TEMPLATE;

Greetings [%given_name%] [%last_name%],

The following circuit was manually failed over to a path that was down, and thus is unavailable. For reference it is now configured as:

[%clr%]

Sincerely,

[%from_signature_name%]

TEMPLATE


$self->{'failover_failed_unknown_template'} = <<TEMPLATE;

Greetings [%given_name%] [%last_name%],

The following circuit attempted to fail over to an alternate path, however was not able to. 
This circuit is currently down.

The details of the circuit as they were before attempted failover:

[%clr%]

Sincerely,

[%from_signature_name%]

TEMPLATE

$self->{'failover_failed_no_backup_template'} = <<TEMPLATE;

Greetings [%given_name%] [%last_name%],

This circuit was affected by an outage that would cause it to failover, however no alternative path was found.
The following circuit is currently down. 

The details of the circuit as they were before attempted failover:

[%clr%]

Sincerely,

[%from_signature_name%]

TEMPLATE

$self->{'failover_failed_path_down_template'} = <<TEMPLATE;

Greetings [%given_name%] [%last_name%],

This circuit attempted to failover, however did not succeed because the alternative path is also down.

The following circuit is currently down. 

The details of the circuit as they were before attempted failover:

[%clr%]

Sincerely,

[%from_signature_name%]

TEMPLATE

$self->{'return_to_primary_template'} = <<TEMPLATE;

Greetings [%given_name%] [%last_name%],

This circuit has been migrated back to its primary from backup due to the circuit preferences.

The details of the circuit are below:

[%clr%]

Sincerely,

[%from_signature_name%]
TEMPLATE

}

=head2 C<_process_config_file>

Configures OESS::Syncer Object from config file

=cut

sub _process_config_file {
    my $self = shift;

    my $config = GRNOC::Config->new( config_file => $self->{'config_file'} );

    $self->{'url'}    = $config->get('/config/websvc/@url')->[0];
    $self->{'user'}   = $config->get('/config/websvc/@user')->[0];
    $self->{'passwd'} = $config->get('/config/websvc/@password')->[0];
    $self->{'realm'}  = $config->get('/config/websvc/@realm')->[0];
    $self->{'from_name'} = $config->get('/config/smtp/@from_name')->[0];
    $self->{'from_address'} = $config->get('/config/smtp/@from_address')->[0];
    return;
}

=head2 C<_connect_services_>

Connects to data.cgi webservice for OESS to retrieve circuit information

=cut

sub _connect_services {
    my $self = shift;

    my $websvc = GRNOC::WebService::Client->new(
        url     => $self->{'url'},
        uid     => $self->{'user'},
        passwd  => $self->{'passwd'},
        realm   => $self->{'realm'},
        usePost => 0
    );
    #warn Dumper ($websvc);
    $self->{'ws'} = $websvc;
    my $db = OESS::Database->new();
    $self->{'db'} = $db;

    #$self->{'from_address'} = 'oess@' . $db->get_local_domain_name();
}

sub get_notification_data {
    
    my $self   = shift;
    my %args = @_;
    my $ws = $self->{'ws'};
    #warn Dumper($ws);
    my $ckt    = $args{'circuit'};
    my $username;
    
    my $user_id;
    my $details = $ws->get_circuit_details( action=> 'get_circuit_details', circuit_id => $ckt->{'circuit_id'})->{'results'};
    unless($details){
        warn "No circuit details found, returning";
        return;
    }
    #warn Dumper ($details);
    $user_id = $details->{'user_id'};
    my $clr = $ws->generate_clr(action=> 'generate_clr', circuit_id => $ckt->{'circuit_id'} )->{'results'}->{'clr'} ;
    unless ($clr){
        warn "No CLR for $ckt->{'circuit_id'} ?";
    }
    #warn Dumper ($clr);
    my $email_address;

    
    my $workgroup_members = $ws->get_workgroup_members(action=>'get_workgroup_members', workgroup_id => $details->{'workgroup_id'})->{'results'};
    
    unless($workgroup_members){
        warn "No workgroup members found, returning";
        return;
    }

    foreach my $member (@$workgroup_members){
        if ($member->{'user_id'} == $user_id)
          {
              $username = $member->{'username'};
              #$email_address = $member->{'email_address'};
          }
    }

    my $circuit = { 'circuit_id' => $details->{'circuit_id'},
                    'workgroup_id' => $details->{'workgroup_id'},
                    'name' => $details->{'name'},
                    'description' => $details->{'description'},
                    'clr' => $clr
                  };
    return ({  'username'=> $username, 'last_modified' => $details->{'last_edited'}, 'clr' => $clr, 'workgroup' => $details->{'workgroup'}->{'name'}, 'affected_users' => $workgroup_members, 'circuit'=> $circuit  });
}


sub _send_notification {

    my $self = shift;
    my %args = @_;
    
    my $body = $args{'body'};
    #warn Dumper ($body);
    my $message = MIME::Lite->new(
                                  From => $self->{'from_address'},
                                  To => $args{'to'},
                                  Subject => $args{'subject'},
                                  Type => 'text/plain',
                                  Data => uri_unescape($body) );
    $message->send('smtp','localhost');
   
}

sub notify_failover{
    my $self = shift;
    my ($circuit,$success) = @_;
        
    my $circuit_notification_data = $self->get_notification_data( circuit => $circuit );   
    #$circuit->{'clr'} = $circuit_notification_data->{'clr'};
    #warn "$success";
    foreach my $user ( @{$circuit_notification_data->{'affected_users'} } ){

        $self->send_notification( 
                                           notification_type =>"failover_$success",
                                           username => $circuit_notification_data->{'username'},
                                           contact_data => $user,
                                           circuit_data => $circuit_notification_data->{'circuit'}
                                          
                                          );
    }

    

}


1;
