#!/usr/bin/perl
use strict;
use warnings;

package OESS::Notification;

use URI::Escape;
use OESS::Database;
use XML::Simple;
use Data::Dumper;
use MIME::Lite;
use Template;
use Switch;
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

GRNOC:OESS::Notification 1.0.9

=cut

our $VERSION = '1.0.9';

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
    

    dbus_signal( "circuit_provision",[ [ "dict", "string", ["variant"] ] ],['string'] );
    dbus_signal( "circuit_modified", [ [ "dict", "string", ["variant"] ] ] );
    dbus_signal( "circuit_removed", [ [ "dict", "string", ["variant"] ] ], ['string'] );
    dbus_signal( "circuit_change_path", [ [ "dict", "string", ["variant"] ] ], ['string'] );
    dbus_signal( "circuit_restored", [['dict', 'string', ["variant"]]],['string']);
    dbus_signal( "circuit_down", [['dict', 'string', ["variant"]]],['string']);
    dbus_signal( "circuit_unknown", [['dict', 'string', ["variant"]]],['string']);

    dbus_method( "circuit_notification", [["dict","string",["variant"]]],["string"]);

    return $self;
}

=head2 C<circuit_provision()>

dbus_method circuit_provision, sends a notification, and emits a signal that circuit has been provisioned

=over

=item circuit

hashref containing circuit data, minimally at least the circuit_id

=back

=cut

sub circuit_notification {
    my $self    = shift;
    my $circuit = shift;

    my $circuit_notification_data = $self->get_notification_data( circuit => $circuit );
    if(!defined($circuit_notification_data)){
	warn "Unable to get circuit data for circuit: " . $circuit->{'circuit_id'};
	return;
    }
    my $subject = "OESS Notification: Circuit '" . $circuit_notification_data->{'circuit'}->{'description'} . "' ";
 
    switch($circuit->{'type'}){
	case "provisioned"{
	    $subject .= "has been provisioned";
	    $self->emit_signal( "circuit_provision", $circuit );
	}case "removed" {
	    $subject .= "has been removed";
	    $self->emit_signal( "circuit_removed", $circuit );
	}case "modified" {
	    $subject .= "has been edited";
	    $self->emit_signal( "circuit_modified", $circuit );
	}case "change_path" {
	    $subject .= "has changed to " . $circuit_notification_data->{'circuit'}->{'active_path'} . " path";
	    $self->emit_signal( "circuit_change_path", $circuit );
	}case "restored" {
	    $subject .= "has been restored";
	    $self->emit_signal( "circuit_restored", $circuit );
	}case "down" {
	    $subject .= "is down";
	    $self->emit_signal( "circuit_down", $circuit );
	}case "unknown" {
	    $subject .= "is in an unknown state";
	    $self->emit_signal( "circuit_unknown", $circuit );
	}
    }
    $circuit_notification_data->{'subject'} = $subject;
    $self->send_notification( $circuit_notification_data );

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
    my $data = shift;

    my @to_list     = ();
    my $desc        = $data->{'circuit'}->{'description'};

    my $vars = {
                workgroup           => $data->{'workgroup'},
                circuit_description => $data->{'circuit'}->{'description'},
                clr                 => $data->{'clr'},
                from_signature_name => $self->{'from_name'},
                type => $data->{'circuit'}->{'type'},
		reason => $data->{'circuit'}->{'reason'},
		active_path => $data->{'circuit'}->{'active_path'},
		user => $data->{'last_user'},
               };

    my $body;

    $self->{'tt'}->process( "$self->{'template_path'}/notification_templates.tmpl", $vars, \$body ) ||  warn $self->{'tt'}->error();
    
    
    foreach my $user ( @{ $data->{'affected_users'} } ) {
        push( @to_list, $user->{'email_address'} );
    }
    my $to_string = join( ",", @to_list );

    $self->_send_notification(
        to      => $to_string,
        body    => $body,
        subject => $data->{'subject'},

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

    my $ckt = $args{'circuit'};
    my $username;

    my $user_id;
    my $details = $db->get_circuit_details( circuit_id => $ckt->{'circuit_id'} );
    unless ($details) {
        warn "No circuit details found, returning";
        return;
    }

    $user_id = $details->{'user_id'};
    my $clr = $db->generate_clr( circuit_id => $ckt->{'circuit_id'} );
    unless ($clr) {
        warn "No CLR for $ckt->{'circuit_id'} ?";
    }

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
        }
    }

    $details->{'reason'} = $ckt->{'reason'};
    $details->{'status'} = $ckt->{'status'};
    $details->{'type'} = $ckt->{'type'};
    return (
        {
            'username'       => $username,
            'last_modified'  => $details->{'last_edited'},
            'clr'            => $clr,
            'workgroup'      => $details->{'workgroup'}->{'name'},
            'affected_users' => $workgroup_members,
            'circuit'        => $details
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

    my $message = MIME::Lite->new(
        From    => $self->{'from_address'},
        To      => $args{'to'},
        Subject => $args{'subject'},
        Type    => 'text/plain',
        Data    => uri_unescape($body)
    );

    $message->send( 'smtp', 'localhost' );

}


1;
