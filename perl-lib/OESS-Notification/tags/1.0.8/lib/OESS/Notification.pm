use strict;
use warnings;

package OESS::Notification;

use URI::Escape;
use OESS::Database;
use XML::Simple;
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

GRNOC:OESS::Notification 1.0.8

=cut

our $VERSION = '1.0.8';

=head1 SYNOPSIS

Object handles Notification Functions required for OE-SS.

=cut 

=head2 C<new()>

new instantiation of OESS:Notification. Requires a service and a config_file to be passed to it.

=over

=item config_file (optional)

The path on disk to the configuration file for database connection
information. This defauls to "/etc/oess/database.xml".

=item service

The Net::DBus Service exported by the script calling this

=item template_path (optional)

path to the notification template file, defaults to absolute path /usr/share/oess-core

=back

=cut

sub new {
    my $that = shift;
    my $class = ref($that) || $that;

    #my $service = shift;
    my %args    = (
                   config_file => 'etc/oess/database.xml',
                   service => undef,
                   template_path => '/usr/share/oess-core/',
                   @_,
                   );


    my $service = $args{'service'};

    #my $self  = \%args;

    my $self = $class->SUPER::new( $service, "/controller1" );
    $self->{'config_file'} = $args{'config_file'};
    $self->{'template_path'} = $args{'template_path'};
    return if !defined( $self->{'config_file'} );

    $self->{'tt'} = Template->new(ABSOLUTE=>1);

    bless $self, $class;

    $self->_process_config_file();
    $self->_connect_services();
    

    dbus_signal( "signal_circuit_provision",
        [ [ "dict", "string", ["variant"] ] ],
        ['string'] );
    dbus_signal( "signal_circuit_modify",
        [ [ "dict", "string", ["variant"] ] ] );
    dbus_signal( "signal_circuit_decommission",
        [ [ "dict", "string", ["variant"] ] ],
        ['string'] );
    dbus_signal( "signal_circuit_failover",
        [ [ "dict", "string", ["variant"] ] ],
        ['string'] );

    dbus_method( "circuit_provision", [ [ "dict", "string", ["variant"] ] ],
        ['string'] );
    dbus_method( "circuit_modify", [ [ "dict", "string", ["variant"] ] ],
        ['string'] );
    dbus_method( "circuit_decommission", [ [ "dict", "string", ["variant"] ] ],
        ['string'] );
    dbus_method( "circuit_failover", [ [ "dict", "string", ["variant"] ] ],
        ['string'] );
    dbus_method( "circuit_restore_to_primary",
        [ [ "dict", "string", ["variant"] ] ],
        ['string'] );

    return $self;
}

=head2 C<circuit_provision()>

dbus_method circuit_provision, sends a notification, and emits a signal that circuit has been provisioned

=over

=item circuit

hashref containing circuit data, minimally at least the circuit_id

=back

=cut

sub circuit_provision {
    my $self    = shift;
    my $circuit = shift;

    my $circuit_notification_data =
      $self->get_notification_data( circuit => $circuit );

    #$circuit->{'clr'} = $circuit_notification_data->{'clr'};

    $self->send_notification(
        to                => $circuit_notification_data->{'affected_users'},
        notification_type => 'provision',
        workgroup         => $circuit_notification_data->{'workgroup'},
        circuit_data      => $circuit_notification_data->{'circuit'},

    );

    $self->emit_signal( "signal_circuit_provision", $circuit );

}

=head2 C<circuit_modify()>

dbus_method circuit_modify, sends a notification, and emits a signal that circuit has been modified

=over

=item circuit

hashref containing circuit data, minimally at least the circuit_id

=back

=cut


sub circuit_modify {
    my $self    = shift;
    my $circuit = shift;

    warn("in circuit modify");

    my $circuit_notification_data =
      $self->get_notification_data( circuit => $circuit );

    #$circuit
    #$circuit->{'clr'} = $circuit_notification_data->{'clr'};
    #foreach my $user ( @{$circuit_notification_data->{'affected_users'} } ){

    $self->send_notification(
        to                => $circuit_notification_data->{'affected_users'},
        notification_type => 'modify',
        workgroup         => $circuit_notification_data->{'workgroup'},
        circuit_data      => $circuit_notification_data->{'circuit'}
    );

    $self->emit_signal( "signal_circuit_modify", $circuit );

}

=head2 C<circuit_decommission()>

dbus_method circuit_decommision, sends a notification, and emits a signal that circuit has been decommissioned

=over

=item circuit

hashref containing circuit data, minimally at least the circuit_id

=back

=cut

sub circuit_decommission {
    my $self    = shift;
    my $circuit = shift;

    my $circuit_notification_data =
      $self->get_notification_data( circuit => $circuit );

    $self->send_notification(
        to                => $circuit_notification_data->{'affected_users'},
        notification_type => 'decommission',
        workgroup         => $circuit_notification_data->{'workgroup'},
        circuit_data      => $circuit_notification_data->{'circuit'}

    );

    #in case anything needs to listen to this event
    $self->emit_signal( "signal_circuit_decommission", $circuit );

}

=head2 C<circuit_modify()>

dbus_method circuit_modify, sends a notification, and emits a signal that circuit has been modified

=over

=item circuit

hashref containing circuit data, minimally at least the circuit_id, and failover_type. If failover_type is manual or a manual forced type, include requested_by

=back

=cut

sub circuit_failover {
    my $self = shift;
    my ($circuit) = @_;

    my $circuit_notification_data =
      $self->get_notification_data( circuit => $circuit );

    my $notification_type = "failover_" . $circuit->{'failover_type'};
    if ( $circuit->{'failover_type'} = 'forced' && $circuit->{'requested_by'} )
    {
        $notification_type = "failover_forced";
    }

    $self->send_notification(
        to                => $circuit_notification_data->{'affected_users'},
        notification_type => $notification_type,
        workgroup         => $circuit_notification_data->{'workgroup'},
        circuit_data      => $circuit_notification_data->{'circuit'},
        requested_by      => $circuit->{'requested_by'}
    );

    #in case anything needs to listen to this event
    $self->emit_signal( "signal_circuit_failover", $circuit );

}

=head2 C<circuit_restore_to_primary()>

dbus_method circuit_restore_to_primary, sends a notification, and emits a signal that circuit has been restored to primary

=over

=item circuit

hashref containing circuit data, minimally at least the circuit_id

=back

=cut

sub circuit_restore_to_primary {
    my $self = shift;
    my ($circuit) = @_;

    my $circuit_notification_data =
      $self->get_notification_data( circuit => $circuit );

    my $notification_type = "restore_to_primary";

    $self->send_notification(
        to                => $circuit_notification_data->{'affected_users'},
        notification_type => $notification_type,
        workgroup         => $circuit_notification_data->{'workgroup'},
        circuit_data      => $circuit_notification_data->{'circuit'},
        requested_by      => $circuit->{'requested_by'}
    );

    #in case anything needs to listen to this event
    $self->emit_signal( "signal_circuit_failover", $circuit );

}

=head2 C<send_notification()>

sends a notification

=over

=item circuit_data

hashref containing circuit data needed for the notification

=item workgroup

string of name of workgroup

=item to

arrayref of hashrefs minimally containing the  email_address key value pair 

=back

=cut


sub send_notification {
    my $self = shift;

    my %args = (
        notification_type => undef,
        circuit_data      => undef,
        workgroup => undef,
        #contact_data => undef,
        to => [],
        @_,
    );
    my @to_list     = ();
    my $desc        = $args{'circuit_data'}{'description'};
    my $subject_map = {
        'modify'    => "OESS Notification: Circuit " . $desc . " Modified",
        'provision' => "OESS Notification: Circuit " . $desc . " Provisioned",
        'decommission' => "OESS Notification: Circuit " 
          . $desc
          . " Decommissioned",
        'restore_to_primary' => "OESS Notification: Circuit " 
          . $desc
          . " Restored to Primary Path",
        'failover_failed_unknown' => "OESS Notification: Circuit " 
          . $desc
          . " is down",
        'failover_failed_no_backup' => "OESS Notification: Circuit " 
          . $desc
          . " is down",
        'failover_failed_path_down' => "OESS Notification: Circuit " 
          . $desc
          . " is down",
        'failover_success' => "OESS Notification: Circuit " 
          . $desc
          . " Successful Failover to alternate path",
        'failover_manual_success' => "OESS Notification: Circuit " 
          . $desc
          . " Successful Failover to alternate path",
        'failover_forced' => "OESS Notification: Circuit " 
          . $desc
          . " Manual Failover to down path",

    };

    my $vars = {
                workgroup           => $args{'workgroup'},
                circuit_description => $args{'circuit_data'}{'descriptionOB'},
                clr                 => $args{'circuit_data'}{'clr'},
                from_signature_name => $self->{'from_name'},
                type => $args{'notification_type'}
               };

    my $body;
    

    $self->{'tt'}->process( "$self->{'template_path'}/notification_templates.tmpl", $vars, \$body ) ||  warn $self->{'tt'}->error();
    
    
    foreach my $user ( @{ $args{'to'} } ) {
        push( @to_list, $user->{'email_address'} );
    }
    my $to_string = join( ",", @to_list );

    $self->_send_notification(
        to      => $to_string,
        body    => $body,
        subject => $subject_map->{ $args{'notification_type'} },

    );
    return 1;
}


=head2 C<_process_config_file>

Configures OESS::Syncer Object from config file


=cut

sub _process_config_file {
    my $self = shift;

    #my $config = GRNOC::Config->new( config_file => $self->{'config_file'} );
    my $config = XML::Simple::XMLin($self->{'config_file'});

    $self->{'from_name'}    = $config->{'smtp'}->{'from_name'};
    $self->{'from_address'} = $config->{'smtp'}->{'from_address'};
    
    return;
}

=head2 C<_connect_services_>

Connects to OESS Database for OESS to retrieve circuit information

=cut

sub _connect_services {
    my $self = shift;

    my $db = OESS::Database->new();
    $self->{'db'} = $db;

    #$self->{'from_address'} = 'oess@' . $db->get_local_domain_name();
}

=head2 C<get_notification_data()>

calls database to retrieve circuit details, users affected

=over

=item circuit

hashref containing circuit data, minimally at least the circuit_id

=back

=cut

sub get_notification_data {

    my $self = shift;
    my %args = @_;
    my $db   = $self->{'db'};

    #warn Dumper($ws);
    my $ckt = $args{'circuit'};
    my $username;

    my $user_id;
    my $details = $db->get_circuit_details(
        action     => 'get_circuit_details',
        circuit_id => $ckt->{'circuit_id'}
    );
    unless ($details) {
        warn "No circuit details found, returning";
        return;
    }

    #warn Dumper ($details);
    $user_id = $details->{'user_id'};
    my $clr = $db->generate_clr(
        action     => 'generate_clr',
        circuit_id => $ckt->{'circuit_id'}
    );
    unless ($clr) {
        warn "No CLR for $ckt->{'circuit_id'} ?";
    }

    #warn Dumper ($clr);
    my $email_address;

    my $workgroup_members = $db->get_users_in_workgroup(
           workgroup_id => $details->{'workgroup_id'}
    );

    unless ($workgroup_members) {
        warn "No workgroup members found, returning";
        return;
    }

    foreach my $member (@$workgroup_members) {
        if ( $member->{'user_id'} == $user_id ) {
            $username = $member->{'username'};

            #$email_address = $member->{'email_address'};
        }
    }

    my $circuit = {
        'circuit_id'   => $details->{'circuit_id'},
        'workgroup_id' => $details->{'workgroup_id'},
        'name'         => $details->{'name'},
        'description'  => $details->{'description'},
        'clr'          => $clr
    };
    return (
        {
            'username'       => $username,
            'last_modified'  => $details->{'last_edited'},
            'clr'            => $clr,
            'workgroup'      => $details->{'workgroup'}->{'name'},
            'affected_users' => $workgroup_members,
            'circuit'        => $circuit
        }
    );
}

=head2 C<_send_notification>

handles the actual delivery of notifications

=over

=item body

text of email

=item to

comma separated list of addresses to send to

=item subject

subject of email

=back

=cut

sub _send_notification {

    my $self = shift;
    my %args = @_;

    my $body = $args{'body'};

    #warn Dumper ($body);
    my $message = MIME::Lite->new(
        From    => $self->{'from_address'},
        To      => $args{'to'},
        Subject => $args{'subject'},
        Type    => 'text/plain',
        Data    => uri_unescape($body)
    );
    $message->send( 'smtp', 'localhost' );

}

#entry point for failovers from fwdctl

=head2 C<notify_failover()>

method called from reaction to fwdctl signal emission of a failover occurring

=over

=item circuit

hashref, circuit_id is represented in fwdctl as the circuit->{'id'}

=back

=cut



sub notify_failover {
    my $self = shift;
    my ($circuit) = @_;

    

    #warn Dumper ($circuit);

    my $circuit_notification_data = $self->get_notification_data(
        circuit => { circuit_id => $circuit->{'id'} } );

    #$circuit->{'clr'} = $circuit_notification_data->{'clr'};

    $self->send_notification(
        to                => $circuit_notification_data->{'affected_users'},
        workgroup         => $circuit_notification_data->{'workgroup'},
        circuit_data      => $circuit_notification_data->{'circuit'},
        notification_type => "failover_" . $circuit->{'failover_type'},
    );

}

1;
