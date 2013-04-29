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
    my %args  = @_;
    my $self  = \%args;

    return if !defined( $self->{'config_file'} );

    bless $self, $class;

    $self->_process_config_file();
    $self->_connect_services();
    $self->_build_templates();
    
    return $self;
}

sub send_notification {
    my $self= shift;
    
    my %args = (
                notification_type => undef,
                circuit_data => undef,
                contact_data => undef,
                @_
               );
    
    

    my $subject_map = {
                        'failover' => "OESS Notification: Circuit Failover",
                        'modify' => "OESS Notification: Circuit Modified",
                        'provision' => "OESS Notification: Circuit ".$args{'circuit_data'}{'circuit_name'}." Provisioned",
                        'decommission' => "OESS Notification: Circuit Decommissioned"
                       };

    my $vars = {
                workgroup_name => $args{'contact_data'}{'workgroup_name'},
                circuit_clr => $args{'circuit_data'}{'clr'},
                from_signature_name => $self->{'from_name'},
                given_name => $args{'contact_data'}{'given_name'},
                last_name => $args{'contact_data'}{'last_name'}
               };

    my $body;
    my $template = $args{'notification_type'} . '_template';
    
    $self->{'tt'}->process(\$self->{$template}, $vars, \$body);
    
    $self->_send_notification(  body => $body,
                                 subject => $subject_map->{ $args{'notification_type'} }, 
                                 email_address => $args{'contact_data'}{'email_address'}
                                );
    return 1;
}


sub _build_templates {

    my $self = shift;

    $self->{'tt'} = Template->new();

    $self->{'provision_template'} = <<TEMPLATE;

Greetings [%given_name%],[%last_name%],

I'm writing to notify you that the following circuit has been provisioned in workgroup [%workgroup_name%]: 

[%circuit_clr%]

Sincerely,

[%from_signature_name%]

TEMPLATE

      $self->{'decomission_template'} = <<TEMPLATE;

Greetings [%given_name%],[%last_name%],

The following circuit has been decomissioned in workgroup [%workgroup_name%]: 

[%circuit_clr%]

Sincerely,

[%from_signature_name%]

TEMPLATE


$self->{'modify_template'} = <<TEMPLATE;

Greetings [%given_name%] [%last_name%]

The following circuit has been modified in workgroup [%workgroup_name%]

[%circuit_clr%]

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

    $self->{'ws'} = $websvc;
    my $db = OESS::Database->new();
    $self->{'db'} = $db;

    #$self->{'from_address'} = 'oess@' . $db->get_local_domain_name();
}

sub get_notification_data {
    my $self   = shift;
    my %args = @_;
    my $ws;
    my $ckt    = $args{'circuit'};
    my $username;
    my $user_id;
    my $details = $ws->get_circuit_details( action=> 'get_circuit_details', circuit_id => $ckt->{'circuit_id'})->{'results'};

    my $clr = $ws->get_circuit_clr(action=> 'get_circuit_clr', circuit_id => $ckt->{'circuit_id'})->{'results'} ;
    my $email_address;

    #my $user_id = $username;
    
    my $workgroup_members = $ws->get_workgroup_members(action=>'get_workgroup_members', workgroup_id => $details->{'workgroup_id'})->{'results'};

    foreach my $member (@$workgroup_members){
        if ($member->{'user_id'} == $user_id)
          {
              $username = $member->{'username'};
              #$email_address = $member->{'email_address'};
          }
    }

    return ({  'username'=> $username, 'last_modified' => $details->{'last_edited'}, 'affected_users' => $workgroup_members });
}


sub _send_notification {

    my $self = shift;
    my %args = @_;
    
    my $body = $args{'body'};

    my $message = MIME::Lite->new(
                                  From => $self->{'from_address'},
                                  To => $args{'email_address'},
                                  Subject => $args{'subject'},
                                  Type => 'text/plain',
                                  Data => uri_unescape($body) );
    $message->send('smtp','localhost');
    
    
    

}

1;
