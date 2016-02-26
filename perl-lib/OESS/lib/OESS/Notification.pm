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
use DateTime;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::WebService::Regex;
use OESS::Circuit;
use Log::Log4perl;



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
    
    my %args    = (
        config_file => '/etc/oess/database.xml',
        service => undef,
        template_path => '/usr/share/oess-core/',
        @_,
        );
    
    $self->{'config_file'} = $args{'config_file'};
    $self->{'template_path'} = $args{'template_path'};
    
    return if !defined( $self->{'config_file'} );
    
    if(!defined($self->{'config'})){
        $self->{'config'} = "/etc/oess/database.xml";
    }

    $self->{'tt'} = Template->new(ABSOLUTE=>1);
    $self->{'log'} = Log::Log4perl->get_logger("OESS.Notification");

    bless $self, $class;

    $self->_process_config_file();
    $self->_connect_services();
        
    my $notification_dispatcher = GRNOC::RabbitMQ::Dispatcher->new( host => $self->{'db'}->{'rabbitMQ'}->{'host'},
                                                                    port => $self->{'db'}->{'rabbitMQ'}->{'port'},
                                                                    user => $self->{'db'}->{'rabbitMQ'}->{'user'},
                                                                    pass => $self->{'db'}->{'rabbitMQ'}->{'pass'},
                                                                    exchange => 'OESS',
                                                                    queue => 'OF.Notification.RPC');

    $self->register_rpc_methods( $notification_dispatcher );

    $self->{'notification_dispatcher'} = $notification_dispatcher;

    my $notification_events = GRNOC::RabbitMQ::Dispatcher->new( host => $self->{'db'}->{'rabbitMQ'}->{'host'},
                                                                port => $self->{'db'}->{'rabbitMQ'}->{'port'},
                                                                user => $self->{'db'}->{'rabbitMQ'}->{'user'},
                                                                pass => $self->{'db'}->{'rabbitMQ'}->{'pass'},
                                                                exchange => 'OESS',
                                                                queue => 'OF.FWDCTL.event');

    $self->register_notification_events( $notification_events );

    $self->{'notification_events'} = $notification_events;
    
    return $self;

}


sub register_notification_events{
    my $self = shift;
    my $d = shift;
    
    $self->{'log'}->debug("Register Notification events");
    my $method = GRNOC::RabbitMQ::Method->new( name => "circuit_notification",
                                               callback => sub {$self->circuit_notification(@_) },
                                               description => "Signals circuit notification event");

    $method->add_input_parameter( name => "type",
                                  description => "the type of circuit notification event",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::TEXT);

    $d->register_method($method);

    $method->add_input_parameter( name => "link_name",
                                  description => "Name of the link",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::TEXT);
    
    $d->register_method($method);

    $method->add_input_parameter( name => "affected_circuits",
                                  description => "List of circuits affected by the event",
                                  required => 1,
                                  schema => { 'type' => 'array'});
    
    $d->register_method($method);

    $method->add_input_parameter( name => "no_reply",
                                  description => "",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);
    
    $d->register_method($method);
}


sub register_rpc_methods{
    my $self = shift;
    my $d = shift;
    
    $self->{'log'}->debug("Registering Notification RPC");

    my $method = GRNOC::RabbitMQ::Method->new( name => "circuit_notification",
                                               callback => sub {$self->circuit_notification(@_) },
                                               description => "Sends circuit notification");


    $method->add_input_parameter( name => "status",
                                  description => "Status of the circuit",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::TEXT);
                                  

    $d->register_method($method);

    $method->add_input_parameter( name => "removed_by",
                                  description => "User who generated the circuit notification",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::TEXT);

    $d->register_method($method);

    $method->add_input_parameter( name => "type",
                                  description => "the type of circuit notification event",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::TEXT);

    $d->register_method($method);
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
    my $m_ref = shift;
    my $p_ref = shift;

    my $type = $p_ref->{'type'}{'value'};
    my $link_name= $p_ref->{'link_name'}{'value'};
    my $affected_circuits= $p_ref->{'affected_circuits'}{'value'};
    my $no_reply= $p_ref->{'no_reply'}{'value'};

    my $circuit;
    $self->{'log'}->debug("Sending Circuit Notification: " . Data::Dumper::Dumper($p_ref));
    
    if ($type eq 'link_down' || $type eq 'link_up' ) {
	$self->{'log'}->debug("Sending bulk notifications");
        $self->_send_bulk_notification($p_ref);
        return;
    }

    $circuit = $p_ref;
    my $circuit_notification_data = $self->get_notification_data( circuit => $circuit );
    if (!defined($circuit_notification_data)) {
        $self->{'log'}->error("Unable to get circuit data for circuit: " . $circuit->{'circuit_id'});
	return {status => 0};;
    }

    my $subject = "OESS Notification: Circuit '" . $circuit_notification_data->{'circuit'}->{'description'} . "' ";
    my $workgroup = $circuit_notification_data->{'workgroup'};

    $self->{'log'}->debug("Sending circuit with subject: " . $subject);
    $self->{'log'}->debug("Sending to workgroup: " . $workgroup);
    $self->{'log'}->debug("Type: " . $circuit->{'type'});

    switch($circuit->{'type'} ) {
        case "provisioned"{
	    $subject .= "has been provisioned in workgroup: $workgroup ";
	    $self->{'notification_events'}( type => "circuit_provision", circuit => $circuit );
	}
	case "removed" {
	    $subject .= "has been removed from workgroup: $workgroup";
	    $self->{'notification_events'}( type => "circuit_removed", circuit => $circuit );
	}
	case "modified" {
	    $subject .= "has been edited in workgroup: $workgroup";
	    $self->{'notification_events'}( type => "circuit_modified", circuit => $circuit );
	}
	case "change_path" {
	    $subject .= "has changed to " . $circuit_notification_data->{'circuit'}->{'active_path'} . " path in workgroup: $workgroup";
	    $self->{'notification_events'}( type => "circuit_change_path", circuit => $circuit );
	}
	case "restored" {
	    $subject .= "has been restored for workgroup: $workgroup";
	    $self->{'notification_events'}( type => "circuit_restored", circuit => $circuit );
	}
	case "down" {
	    $subject .= "is down for workgroup: $workgroup";
	    $self->{'notification_events'}( type => "circuit_down", circuit => $circuit );
	}
	case "unknown" {
	    $subject .= "is in an unknown state in workgroup: $workgroup";
	    $self->{'notification_events'}( type => "circuit_unknown", circuit => $circuit );
	}
      }

    $circuit_notification_data->{'subject'} = $subject;
    $self->send_notification( $circuit_notification_data );
    
}

sub _send_bulk_notification {
    my $self = shift;
    my $data = shift;
    my $db = $self->{'db'};
    my $circuits = $data->{'affected_circuits'};
    my $link_name = $data->{'link_name'};
    my $workgroup_notifications={};
    my $type = $data->{'type'};

    foreach my $circuit (@$circuits) {
        #build workgroup buckets
        my $circuit_details = $self->get_notification_data(circuit => $circuit);

        if(!defined($circuit_details)){
            return;
        }
        
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


	my $dt = DateTime->now;	
	my $str_date = $dt->day_name() . ", " . $dt->month_name() . " " . $dt->day() . ", " . $dt->year() . ", at " . $dt->hms();
	$self->{'log'}->debug("Using Time String: " . $str_date);
	
        my %vars = (
                    SUBJECT => $subject,
                    base_url => $self->{'base_url'},
                    workgroup           => $workgroup,
                    workgroup_id => $workgroup_notifications->{$workgroup }{'workgroup_id'},
                    from_signature_name => $self->{'from_name'},
                    link_name => $link_name,
                    type => $data->{'type'},
                    circuits => $workgroup_circuits,
                    circuits_on_owned_endpoints => $circuits_on_owned_endpoints,
                    image_base_url => $self->{'image_base_url'},
                    human_time => $str_date
                   );
	$self->{'log'}->debug("using VARS: " . Data::Dumper::Dumper(%vars));

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
		$self->{'log'}->error("INFO: send_bulk_notification: No notification to send as there are no users in workgroup. ");
	    	return 0;
	}
	
	#we determined that there are several cases that can cause
	#send to cause a die
	eval{
	    my $message = MIME::Lite::TT::HTML->new(
		From    => $self->{'from_address'},
		To      => $to_string,
		Subject => $subject,
		Encoding    => 'quoted-printable',
		Timezone => 'UTC',
		Template => {
		    html => $self->{'template_path'} . "/notification_bulk.tt.html",
		    text => $self->{'template_path'} . "/notification_bulk.tmpl"
		},
		TmplParams => \%vars,
		TmplOptions => \%tmpl_options,
		);
	    
	    
	    $message->send( 'smtp', 'localhost' );
	};
	if($@){
	    $self->{'log'}->error("Error sending Notification: " . $@);
	}
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

    $self->{'log'}->debug("send notification: " . Data::Dumper::Dumper($data));

    my @to_list     = ();
    my $desc        = $data->{'circuit'}->{'description'};

    my $dt = DateTime->now;
    my $str_date = $dt->day_name() . ", " . $dt->month_name() . " " . $dt->day() . ", " . $dt->year() . ", at " . $dt->hms();
    $self->{'log'}->debug("Using Time String: " . $str_date);

    my %vars = (
        SUBJECT => $data->{'subject'},
        base_url => $self->{'base_url'},
        circuit_id          => $data->{'circuit'}->{'circuit_id'},
        workgroup           => $data->{'workgroup'},
        workgroup_id        => $data->{'workgroup_id'},
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

    if($to_string eq ''){
    	$self->{'log'}->error("INFO: send_notification: No notification to send as there are no users in workgroup. ");
    	return 0;
    }

    
    eval{
	my $message = MIME::Lite::TT::HTML->new(
	    From    => $self->{'from_address'},
	    To      => $to_string,
	    Subject => $data->{'subject'},
	    Encoding    => 'quoted-printable',
	    Timezone => 'UTC',
	    Template => {
		html => $self->{'template_path'} . "/notification.tt.html",
		text => $self->{'template_path'} . "/notification_templates.tmpl"
	    },
	    TmplParams => \%vars,
	    TmplOptions => \%tmpl_options,
	    );
	
	
	$message->send( 'smtp', 'localhost' );
    };

    if($@){
	$self->{'log'}->error("Error sending Notification: " . $@);
    }

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

	    eval{
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
	    };
	    if($@){
		$self->{'log'}->error("Error sending Notification: " . $@);
	    }
        }
    }

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
    
    $self->{'db'} = OESS::Database->new( config_file => $self->{'config'} );
    
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
        
      $self->{'log'}->debug("get_notification_data: " . $ckt->{'circuit_id'});
      my $user_id;
      my $details = $db->get_circuit_details( circuit_id => $ckt->{'circuit_id'} );
      unless ($details) {
          $self->{'log'}->error("No circuit details found, returning");
          return;
      }
      $self->{'log'}->debug("Circuit Details: " . Data::Dumper::Dumper($details));
      $user_id = $details->{'user_id'};
      my $ockt = OESS::Circuit->new( circuit_id => $ckt->{'circuit_id'}, db => $db);
      my $clr = $ockt->generate_clr();
      unless ($clr) {
          $self->{'log'}->error("No CLR for $ckt->{'circuit_id'} ?");
	  return;
      }

      my $email_address;
      my $workgroup_members = $db->get_users_in_workgroup(
	  workgroup_id => $details->{'workgroup_id'}
	  );

      #unless ($workgroup_members) {
      #    $self->{'log'}->error( "No workgroup members found, returning");
      #    return;
      #}


      foreach my $member (@$workgroup_members) {
          if ( $member->{'user_id'} == $user_id ) {
              $username = $member->{'username'};
          }
      }

      foreach my $endpoint ( @{ $details->{'endpoints'} }  ) {

          my $interface_id = $db->get_interface_id_by_names(node =>$endpoint->{'node'} ,interface => $endpoint->{'interface'} );


	  if(!defined($interface_id)){
	      $self->{'log'}->error("Unable to find interface in DB: " . $endpoint->{'node'} . ":" . $endpoint->{'interface'});
	      return;
	  }
          my $interface = $db->get_interface(interface_id =>$interface_id);
	  if(!defined($interface)){
	      $self->{'log'}->error("unable to find an interface with ID: " . $interface_id);
	      return;
	  }
          my $workgroup_name = $interface->{'workgroup_name'};
	  if(!defined($workgroup_name)){
	      $self->{'log'}->error("No workgroup assigned to interface " . $interface->{'name'});
	  }
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
