#!/usr/bin/perl
use strict;
use warnings;

package OESS::Notification;

use URI::Escape;
use OESS::Database;
use XML::Simple;
use Data::Dumper;
use MIME::Lite::TT::HTML;
#use Template;
use Switch;
use Net::DBus::Exporter qw (org.nddi.notification);
use Net::DBus qw(:typing);
use OESS::Circuit;
use Log::Log4perl;

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
    $self->{'log'} = Log::Log4perl->get_logger("OESS.Notification");

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

=head2 C<circuit_notification()>

dbus_method circuit_provision, sends a notification, and emits a signal that circuit has been provisioned

=over

=item circuit

hashref containing circuit data, minimally at least the circuit_id

=back

=cut

sub circuit_notification {
    my $self    = shift;
    my $dbus_data = shift;
    my $circuit;
    if ($dbus_data->{'type'} eq 'link_down' || $dbus_data->{'type'} eq 'link_up' ) {
        $self->_send_bulk_notification($dbus_data);
        return;
    }

    $circuit = $dbus_data;
    my $circuit_notification_data = $self->get_notification_data( circuit => $circuit );
    if (!defined($circuit_notification_data)) {
        $self->{'log'}->error("Unable to get circuit data for circuit: " . $circuit->{'circuit_id'});
          return;
    }
    my $subject = "OESS Notification: Circuit '" . $circuit_notification_data->{'circuit'}->{'description'} . "' ";
    my $workgroup = $circuit_notification_data->{'workgroup'};

    switch($circuit->{'type'} ) {
        case "provisioned"{
                           $subject .= "has been provisioned in workgroup: $workgroup ";
                           $self->emit_signal( "circuit_provision", $circuit );
                          }
          case "removed" {
                          $subject .= "has been removed from workgroup: $workgroup";
                          $self->emit_signal( "circuit_removed", $circuit );
                         }
          case "modified" {
                             $subject .= "has been edited in workgroup: $workgroup";
                             $self->emit_signal( "circuit_modified", $circuit );
                            }
          case "change_path" {
                                  $subject .= "has changed to " . $circuit_notification_data->{'circuit'}->{'active_path'} . " path in workgroup: $workgroup";
                                  $self->emit_signal( "circuit_change_path", $circuit );
                             }
          case "restored" {
                           $subject .= "has been restored for workgroup: $workgroup";
                           $self->emit_signal( "circuit_restored", $circuit );
                          }
          case "down" {
                       $subject .= "is down for workgroup: $workgroup";
                       $self->emit_signal( "circuit_down", $circuit );
                      }
          case "unknown" {
                          $subject .= "is in an unknown state in workgroup: $workgroup";
                          $self->emit_signal( "circuit_unknown", $circuit );
                         }
      }

    $circuit_notification_data->{'subject'} = $subject;
    $self->send_notification( $circuit_notification_data );

}

sub _send_bulk_notification {
    my $self = shift;
    my $dbus_data = shift;
    my $db = $self->{'db'};
    my $circuits = $dbus_data->{'affected_circuits'};
    my $link_name = $dbus_data->{'link_name'};
    my $workgroup_notifications={};
    my $type = $dbus_data->{'type'};

    foreach my $circuit (@$circuits) {
        #build workgroup buckets
        my $circuit_details = $self->get_notification_data(circuit => $circuit);

        my $owners = $circuit_details->{'endpoint_owners'};

        foreach my $owner (keys %$owners) {
            my $affected_users = $owners->{$owner}->{'affected_users'};
            my $workgroup_id = $owners->{$owner}->{'workgroup_id'};

            unless ($workgroup_notifications->{$owner}) {
                $workgroup_notifications->{$owner} = {};
                $workgroup_notifications->{$owner}{'affected_users'} = $affected_users;
                $workgroup_notifications->{$owner }{'workgroup_id'} = $workgroup_id;
                $workgroup_notifications->{$owner}{'endpoint_owned'}{'circuits'} = [];
            }

            push (@{ $workgroup_notifications->{ $owner }{'endpoint_owned'}{'circuits'} }, $circuit_details->{'circuit'} );

        }

        unless ($workgroup_notifications->{$circuit_details->{'workgroup'} } ) {
            $workgroup_notifications->{$circuit_details->{'workgroup'} } = {};
            $workgroup_notifications->{$circuit_details->{'workgroup'} }{'affected_users'} = $circuit_details->{'affected_users'};
            $workgroup_notifications->{$circuit_details->{'workgroup'} }{'workgroup_id'} = $circuit_details->{'workgroup_id'};
            $workgroup_notifications->{$circuit_details->{'workgroup'} }{'circuits'} = [];
        }

        push (@{ $workgroup_notifications->{$circuit_details->{'workgroup'} }{'circuits'} }, $circuit_details->{'circuit'} );

    }

    foreach my $workgroup (keys %$workgroup_notifications) {
        #split into per workgroup circuit sets
        my @to_list = ();
        my $workgroup_circuits = $workgroup_notifications->{$workgroup}{'circuits'} || [];
        my $circuits_on_owned_endpoints = $workgroup_notifications->{$workgroup}{'endpoint_owned'}{'circuits'} || [];
        my $affected_users = $workgroup_notifications->{$workgroup}{'affected_users'};
        my $subject;
        my $circuit_count = 0;
        if ($workgroup_circuits){
            $circuit_count= scalar (@$workgroup_circuits);
        }
        my $owned_count =0;
        if ($circuits_on_owned_endpoints){
            $owned_count = scalar (@$circuits_on_owned_endpoints);
        }
        switch($type) {
            case ('link_down'){
                $subject = "OESS Notification: Backbone Link $link_name is down. ".$circuit_count." circuits in workgroup $workgroup and ".$owned_count." using ports owned by your workgroup are impacted";
            }
            case ('link_up'){
                $subject = "OESS Notification: Backbone Link $link_name is up. ".$circuit_count." circuits in workgroup $workgroup and ".$owned_count. " using ports owned by your workgroup have been restored to service";
            }
        }


        my $current_time = time;
        #make a human readable timestamp that goes with the epoch timestamp
        
        my @months = qw(January February March April May June July August September October November December);
        my @days = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);
        my ($sec, $min, $hour, $mday, $month, $year, $wday, $yday, $isdst) = localtime($current_time);
        $year += 1900;
        #append a zero to the front of hour, min or sec if it is less than ten
        if ($hour < 10) {$hour = "0".$hour}; if($min < 10) {$min = "0".$min}; if($sec < 10){$sec = "0".$sec}; 
        my $str_date = "$days[$wday], $months[$month] $mday, $year, at $hour:$min:$sec"; 
        my %vars = (
                    SUBJECT => $subject,
                    base_url => $self->{'base_url'},
                    workgroup           => $workgroup,
                    workgroup_id => $workgroup_notifications->{$workgroup }{'workgroup_id'},
                    from_signature_name => $self->{'from_name'},
                    link_name => $link_name,
                    type => $dbus_data->{'type'},
                    circuits => $workgroup_circuits,
                    circuits_on_owned_endpoints => $circuits_on_owned_endpoints,
                    image_base_url => $self->{'image_base_url'},
                    human_time => $str_date
                   );

        my %tmpl_options = ( ABSOLUTE=>1,
                             RELATIVE=>0,
                           );
        my $body;

        #$self->{'tt'}->process( "$self->{'template_path'}/notification_templates.tmpl", $vars, \$body ) ||  warn $self->{'tt'}->error();

        foreach my $user ( @$affected_users ) {
            push( @to_list, $user->{'email_address'} );
        }

        my $to_string = join( ",", @to_list );

	if($to_string eq ''){
	    return;
	}

        my $message = MIME::Lite::TT::HTML->new(
                                                From    => $self->{'from_address'},
                                                To      => $to_string,
                                                Subject => $subject,
                                                Encoding    => 'quoted-printable',
                                                Timezone => 'UTC',
                                                Template => {
                                                             html => "$self->{'template_path'}/notification_bulk.tt.html",
                                                             text => "$self->{'template_path'}/notification_bulk.tmpl"
                                                            },
                                                TmplParams => \%vars,
                                                TmplOptions => \%tmpl_options,
                                               );


        $message->send( 'smtp', 'localhost' );
    }

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

    my $current_time = time;
    #make a human readable timestamp that goes with the epoch timestamp
    my @months = qw(January February March April May June July August September October November December);
    my @days = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);
    my ($sec, $min, $hour, $mday, $month, $year, $wday, $yday, $isdst) = localtime($current_time);
    $year += 1900;
    if ($hour < 10) {$hour = "0".$hour}; if($min < 10) {$min = "0".$min}; if($sec < 10){$sec = "0".$sec};
    my $str_date = "$days[$wday], $months[$month] $mday, $year, at $hour:$min:$sec"; 
    my %vars = (
        SUBJECT => $data->{'subject'},
        base_url => $self->{'base_url'},
        circuit_id          => $data->{'circuit'}->{'circuit_id'},
        workgroup           => $data->{'workgroup'},
        workgroup_id        => $data->{'workgroup_id'}
        circuit_description => $data->{'circuit'}->{'description'},
        clr                 => $data->{'clr'},
        from_signature_name => $self->{'from_name'},
        type => $data->{'circuit'}->{'type'},
        reason => $data->{'circuit'}->{'reason'},
        active_path => $data->{'circuit'}->{'active_path'},
        last_modified_by => "$data->{'last_modified_by'}{'given_names'} $data->{'last_modified_by'}{'family_name'}",
        image_base_url => $self->{'image_base_url'},
        human_time => $str_date
        );
    
      my %tmpl_options = ( ABSOLUTE=>1,
                           RELATIVE=>0,
                         );
      my $body;

      #$self->{'tt'}->process( "$self->{'template_path'}/notification_templates.tmpl", $vars, \$body ) ||  warn $self->{'tt'}->error();

      foreach my $user ( @{ $data->{'affected_users'} } ) {
          push( @to_list, $user->{'email_address'} );
      }

      my $to_string = join( ",", @to_list );

      my $message = MIME::Lite::TT::HTML->new(
                                              From    => $self->{'from_address'},
                                              To      => $to_string,
                                              Subject => $data->{'subject'},
                                              Encoding    => 'quoted-printable',
                                              Timezone => 'UTC',
                                              Template => {
                                                           html => "$self->{'template_path'}/notification.tt.html",
                                                           text => "$self->{'template_path'}/notification_templates.tmpl"
                                                          },
                                              TmplParams => \%vars,
                                              TmplOptions => \%tmpl_options,
                                             );


    $message->send( 'smtp', 'localhost' );

    my $owners = $data->{'endpoint_owners'};
    if ($owners) {
        foreach my $owner (keys %$owners) {
            my @owner_to_list;
            $vars{'workgroup'} = $owner;
            $vars{'workgroup_id'} = $owners->{$owner}{'workgroup_id'};
            #$vars{'affected_users'} = $owners->{$owner}{'affected_users'};
            my $owner_affected_users = $owners->{$owner}{'affected_users'};
            foreach my $user ( @$owner_affected_users ) {
                push( @owner_to_list, $user->{'email_address'} );
            }

            $to_string = join( ",", @owner_to_list );


            my $message = MIME::Lite::TT::HTML->new(
                                                      From    => $self->{'from_address'},
                                                      To      => $to_string,
                                                      Subject => $data->{'subject'},
                                                      Encoding    => 'quoted-printable',
                                                      Timezone => 'UTC',
                                                      Template => {
                                                                   html => "$self->{'template_path'}/notification.tt.html",
                                                                   text => "$self->{'template_path'}/notification_templates.tmpl"
                                                                  },
                                                      TmplParams => \%vars,
                                                      TmplOptions => \%tmpl_options,
                                                     );


            $message->send( 'smtp', 'localhost' );

        }
      }


      #$self->_send_notification(
      #   to      => $to_string,
      #   body    => $body,
      #   subject => $data->{'subject'},

      #);
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
    $self->{'image_base_url'} = $config->{'smtp'}->{'image_base_url'};
    $self->{'base_url'} = $config->{'base_url'};
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
      my $owners = {};
      my $ckt = $args{'circuit'};
      my $username;
        
      my $user_id;
      my $details = $db->get_circuit_details( circuit_id => $ckt->{'circuit_id'} );
      unless ($details) {
          $self->{'log'}->error("No circuit details found, returning");
          return;
      }

      $user_id = $details->{'user_id'};
      my $ockt = OESS::Circuit->new( circuit_id => $ckt->{'circuit_id'}, db => $db);
      my $clr = $ockt->generate_clr();
      unless ($clr) {
          $self->{'log'}->error("No CLR for $ckt->{'circuit_id'} ?");
      }

      my $email_address;

      my $workgroup_members = $db->get_users_in_workgroup(
                                                          workgroup_id => $details->{'workgroup_id'}
                                                         );

      unless ($workgroup_members) {
          $self->{'log'}->error( "No workgroup members found, returning");
          return;
      }

      foreach my $member (@$workgroup_members) {
          if ( $member->{'user_id'} == $user_id ) {
              $username = $member->{'username'};
          }
      }

      foreach my $endpoint ( @{ $details->{'endpoints'} }  ) {

          my $interface_id = $db->get_interface_id_by_names(node =>$endpoint->{'node'} ,interface => $endpoint->{'interface'} );
          my $interface = $db->get_interface(interface_id =>$interface_id);
          my $workgroup_name = $interface->{'workgroup_name'};
          #if the creator of the circuit is the same as the owner of the
          #edge port we won't document them here, and if we already have the workgroup, skip it.
          if ($interface->{'workgroup_id'} == $details->{'workgroup_id'} || $owners->{ $interface->{'workgroup_id'} } ) {
              next;
          }
          $owners->{ $workgroup_name } = {};
          $owners->{ $workgroup_name }{'workgroup_id'} = $interface->{'workgroup_id'};

          my $owner_workgroup_members = $db->get_users_in_workgroup(
                                                                    workgroup_id => $interface->{'workgroup_id'}
                                                                   );
          $owners->{ $workgroup_name }{'affected_users'} = $owner_workgroup_members;
      }



      $details->{'reason'} = $ckt->{'reason'};
      $details->{'status'} = $ckt->{'status'};
      $details->{'type'} = $ckt->{'type'};
      return (
              {
               'username'         => $username,
               'last_modified'    => $details->{'last_edited'},
               'last_modified_by' => $details->{'last_modified_by'},
               'clr'              => $clr,
               'endpoint_owners'  => $owners,
               'workgroup'        => $details->{'workgroup'}->{'name'},
               'workgroup_id'     => $details->{'workgroup_id'},
               'affected_users'   => $workgroup_members,
               'circuit'          => $details
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


}


1;
