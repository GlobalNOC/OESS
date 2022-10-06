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
use GRNOC::RabbitMQ::Client;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::WebService::Regex;
use OESS::RabbitMQ::Client;
use OESS::RabbitMQ::Dispatcher;
use OESS::Circuit;
use OESS::L2Circuit;
use Log::Log4perl;

#new stuff
use OESS::DB;
use OESS::VRF;


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
    my $that  = shift;
    my $class = ref($that) || $that;

    my %args  = (
        config_file => '/etc/oess/database.xml',
        service => undef,
        template_path => '/usr/share/oess-core/',
        @_,
        );

    my $self  = \%args;
    bless $self, $class;
    
    $self->{'config_file'} = $args{'config_file'};
    $self->{'template_path'} = $args{'template_path'};
    
    return if !defined( $self->{'config_file'} );
    
    if(!defined($self->{'config'})){
        $self->{'config'} = "/etc/oess/database.xml";
    }

    $self->{'tt'} = Template->new(ABSOLUTE=>1);
    $self->{'log'} = Log::Log4perl->get_logger("OESS.Notification");

    $self->_process_config_file();
    $self->_connect_services();
        
    my $notification_dispatcher = OESS::RabbitMQ::Dispatcher->new( topic => 'OF.FWDCTL.RPC' );
    $self->_register_notification_events($notification_dispatcher);
    $self->{'notification_dispatcher'} = $notification_dispatcher;

    my $emitter = OESS::RabbitMQ::Client->new( topic => 'OF.Notification.event');
    $self->{'notification_events'} = $emitter;
    
    return $self;
}

=head2 start

=cut

sub start {
    my $self = shift;
    $self->{'log'}->info("Notification.pm is now consuming.");
    $self->{'notification_dispatcher'}->start_consuming();
}

sub _register_notification_events{
    my $self = shift;
    my $d = shift;
    
    $self->{'log'}->debug("Register Notification events");
    my $method = GRNOC::RabbitMQ::Method->new( name => "circuit_notification",
					       topic => 'OF.FWDCTL.event',
                                               callback => sub {$self->circuit_notification(@_) },
                                               description => "Signals circuit notification event");
    $method->add_input_parameter( name => "type",
                                  description => "the type of circuit notification event",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::TEXT);
    $method->add_input_parameter( name => "link_name",
                                  description => "Name of the link",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::TEXT);
    $method->add_input_parameter( name => "affected_circuits",
                                  description => "List of circuits affected by the event",
                                  required => 1,
                                  schema => { 'type' => 'array'});
    $d->register_method($method);

    $self->{'log'}->debug("Register Notification events");
    $method = GRNOC::RabbitMQ::Method->new(
        name        => "review_endpoint_notification",
        topic       => 'OF.FWDCTL.event',
        callback    => sub {$self->review_endpoint_notification(@_) },
        description => "Signals endpoint review required notification event"
    );
    $method->add_input_parameter(
        name => "connection_id",
        description => "Id of related connection",
        required => 1,
        schema => { 'type' => 'integer'}
    );
    $method->add_input_parameter(
        name => "connection_type",
        description => "Type of related connection",
        required => 1,
        pattern => $GRNOC::WebService::Regex::TEXT
    );
    $d->register_method($method);

    $self->{'log'}->debug("Register Notification events");
    $method = GRNOC::RabbitMQ::Method->new( name => "vrf_notification",
                                            topic => 'OF.FWDCTL.event',
                                               callback => sub {$self->vrf_notification(@_) },
                                            description => "Signals vrf notification event");
    $method->add_input_parameter( name => "type",
                                  description => "the type of vrf notification event",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::TEXT);
    $method->add_input_parameter( name => "reason",
                                  description => "the reason for this vrf notification event",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::TEXT);
    $method->add_input_parameter( name => "vrf",
                                  description => "the VRF object we are operating on",
                                  required => 1,
                                  schema => { 'type' => 'integer'});
    $d->register_method($method);
    #Named differently because both Notif and FWDCTL use same topic
    $method = GRNOC::RabbitMQ::Method->new( name => 'is_online',
                                            async => 1,
                                            callback => sub { my $method =shift;
                                                             $method->{'success_callback'}({successful => 1});
                                                         },
                                            description => "Returns the 1 if we are able to connect to this service");
    $d->register_method($method);                                                

}

=head2 review_endpoint_notification

=cut
sub review_endpoint_notification {
    my $self = shift;
    my $method = shift;
    my $params = shift;

    my $subject = "OESS - Administrative Approval Required";

    my $connection = undef;
    my $connection_id = $params->{connection_id}{value};

    if ($params->{connection_type}{value} eq 'circuit') {
        $connection = new OESS::L2Circuit(db => $self->{db_new}, circuit_id => $connection_id);
        if (!defined $connection) {
            $self->{log}->error("L2 connection $connection_id could not be loaded");
            return;
        }
        $connection->load_endpoints;
        $connection->load_users;
        $connection->load_workgroup;
    } else {
        $connection = new OESS::VRF(db => $self->{db_new}, vrf_id => $connection_id);
        if (!defined $connection) {
            $self->{log}->error("L3 connection $connection_id could not be loaded");
            return;
        }
        $connection->load_endpoints;
        $connection->load_users;
        $connection->load_workgroup;
    }
    my $payload = $connection->to_hash;

    return $self->send_review_endpoint_notification(
        subject => $subject,
        connection => $payload,
    );
}

=head2 send_review_endpoint_notification

=cut
sub send_review_endpoint_notification {
    my $self = shift;
    my $args = {
        subject => undef,
        connection => undef,
        connection_type => 'circuit',
        @_
    };

    # TODO load endpoints into $clr
    my $endpoints = [];

    my $dt = DateTime->from_epoch( epoch => $args->{connection}->{last_modified} );
    my $human_time = $dt->day_name() . ", " . $dt->month_name() . " " . $dt->day() . ", " . $dt->year() . ", at " . $dt->hms() . " UTC";

    foreach my $ep (@{$args->{connection}->{endpoints}}) {
        next if ($ep->{state} ne 'in-review');

        $ep->{cloud_interconnect_type} = (defined $ep->{cloud_interconnect_type}) ? $ep->{cloud_interconnect_type} : 'Unkown';
        $ep->{entity} = (defined $ep->{entity}) ? $ep->{entity} : 'Unkown';

        push @$endpoints, $ep;
    }
    warn Dumper($args->{connection});

    my $vars = {
        SUBJECT             => $args->{subject},
        base_url            => $self->{base_url},
        workgroup           => $args->{connection}->{workgroup}->{name},
        description         => $args->{connection}->{description},
        endpoints           => $endpoints,
        from_signature_name => $self->{from_name},
        last_modified_by    => "$args->{connection}->{last_modified_by}->{first_name} $args->{connection}->{last_modified_by}->{last_name}",
        image_base_url      => $self->{image_base_url},
        human_time          => $human_time
    };

    my $tmpl_options = {
        ABSOLUTE=>1,
        RELATIVE=>0,
    };

    # TODO generate $to_string
    my $to_string = 'jonstout@globalnoc.iu.edu';
    eval {
        my $message = MIME::Lite::TT::HTML->new(
            From => $self->{'from_address'},
            To   => $to_string,
            Subject  => $args->{subject},
            Encoding => 'quoted-printable',
            Timezone => 'UTC',
            Template => {
                html => "$self->{template_path}/notification_endpoint_review.tt.html",
                text => "$self->{template_path}/notification_templates_endpoint_review.tmpl"
            },
            TmplParams  => $vars,
            TmplOptions => $tmpl_options,
        );
        $message->send('smtp', 'localhost');
    };
    if ($@) {
        $self->{log}->error("Error sending Notification: " . $@);
    }

    return 1;
}

=head2 vrf_notification

=cut

sub vrf_notification{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $vrf_id = $p_ref->{'vrf'}{'value'};
    my $vrf = OESS::VRF->new( db => $self->{'db_new'}, vrf_id => $vrf_id);
    if(!defined($vrf)){
        $self->{'log'}->error("No VRF was specified");
        return;
    }
    $vrf->load_endpoints;
    $vrf->load_users;
    $vrf->load_workgroup;

    my $subject = "OESS Notification: '" . $vrf->{'description'} . "' ";
    #no bulk notifications for MPLS VRFs
    switch($p_ref->{'type'}{'value'}){
        case "provisioned"{
            $subject .= "provisioned in workgroup: " . $vrf->workgroup()->name();
            $self->{'notification_events'}->vrf_provision( vrf_id => $vrf->vrf_id(), no_reply => 1 );
        }
        case "removed" {
            $subject .= "removed from workgroup: " . $vrf->workgroup()->name();
            $self->{'notification_events'}->vrf_remove( vrf_id => $vrf->vrf_id(), no_reply => 1 );
        }
        case "modified" {
            $subject .= "modified in workgroup: " . $vrf->workgroup()->name();
            $self->{'notification_events'}->vrf_modify( vrf_id => $vrf->vrf_id(), no_reply => 1 );
        }
    }

    $self->send_vrf_notification( subject => $subject,
                                  reason => $p_ref->{'reason'}{'value'},
                                  type => $p_ref->{'type'}{'value'},
                                  vrf => $vrf->to_hash() );

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


    my $circuit;
    $self->{'log'}->debug("Sending Circuit Notification: " . Data::Dumper::Dumper($p_ref));

    $circuit = $p_ref->{'affected_circuits'}{'value'}[0];
    my $circuit_notification_data = $self->get_notification_data( circuit => $circuit );
    if (!defined($circuit_notification_data)) {
        $self->{'log'}->error("Unable to get circuit data for circuit: " . $circuit->{'circuit_id'});
	return {status => 0};;
    }

    my $subject = "OESS Notification: '" . $circuit_notification_data->{'circuit'}->{'description'} . "' ";
    my $workgroup = $circuit_notification_data->{'workgroup'};

    $self->{'log'}->debug("Sending circuit with subject: " . $subject);
    $self->{'log'}->debug("Sending to workgroup: " . $workgroup);
    $self->{'log'}->debug("Type: " . $circuit->{'type'});

    switch($circuit->{'type'} ) {
        case "provisioned"{
            $subject .= "provisioned in workgroup: $workgroup ";
            $self->{'notification_events'}->circuit_provision( circuit => $circuit, no_reply => 1 );
        }
        case "removed" {
            $subject .= "removed from workgroup: $workgroup";
            $self->{'notification_events'}->circuit_remove( circuit => $circuit, no_reply => 1 );
        }
        case "modified" {
            $subject .= "modified in workgroup: $workgroup";
            $self->{'notification_events'}->circuit_modify( circuit => $circuit, no_reply => 1 );
        }
        case "change_path" {
            $subject .= "changed to " . $circuit_notification_data->{'circuit'}->{'active_path'} . " path in workgroup: $workgroup";
            $self->{'notification_events'}->circuit_change_path( circuit => $circuit, no_reply => 1 );
        }
        case "restored" {
            $subject .= "restored for workgroup: $workgroup";
            $self->{'notification_events'}->circuit_restore( circuit => $circuit, no_reply => 1 );
        }
        case "down" {
            $subject .= "down for workgroup: $workgroup";
            $self->{'notification_events'}->circuit_down( circuit => $circuit, no_reply => 1 );
        }
        case "unknown" {
            $subject .= "is in an unknown state in workgroup: $workgroup";
            $self->{'notification_events'}->circuit_unknown( circuit => $circuit, no_reply => 1 );
        }
    }

    $circuit_notification_data->{'subject'} = $subject;
    $self->send_notification( $circuit_notification_data );

}

=head2 send_vrf_notification

=cut

sub send_vrf_notification {
    my $self = shift;
    my %params = @_;
    my $subject = $params{'subject'};
    my $vrf = $params{'vrf'};
    my $type = $params{'type'};
    my $reason = $params{'reason'};

    $self->{'log'}->debug("send vrf notification: " . Data::Dumper::Dumper($vrf));

    my @to_list     = ();
    my $desc        = $vrf->{'description'};

    my $dt = DateTime->now;
    my $str_date = $dt->day_name() . ", " . $dt->month_name() . " " . $dt->day() . ", " . $dt->year() . ", at " . $dt->hms() . " UTC";
    $self->{'log'}->debug("Using Time String: " . $str_date);

    my $clr = "";
    $clr .= "VRF: " . $vrf->{'name'} . "\n";
    my $created = DateTime->from_epoch(epoch => $vrf->{'created'});
    my $str_created = $created->day_name() . ", " . $created->month_name() . " " . $created->day() . ", " . $created->year() . ", at " . $created->hms() . " UTC";
    $clr .= "Created By: " . $vrf->{'created_by'}->{'first_name'} . " " . $vrf->{'created_by'}->{'family_name'} . " at " . $str_created . " for workgroup " . $vrf->{'workgroup'}->{'name'} . "\n";
    my $modified = DateTime->now;
    my $str_modified = $modified->day_name() . ", " . $modified->month_name() . " " . $modified->day() . ", " . $modified->year() . ", at " . $modified->hms() . " UTC\n";
    $clr .= "Last Modified By: " . $vrf->{'last_modified_by'}->{'first_name'} . " " . $vrf->{'last_modified_by'}->{'family_name'} . " at " . $str_modified . " UTC\n";
    $clr .= "Endpoints: \n";
    foreach my $ep (@{$vrf->{'endpoints'}}){
        $clr .= "  " . $ep->{'node'} . " - " . $ep->{'interface'} . " VLAN " . $ep->{'tag'} . "\n";
        foreach my $peer (@{$ep->{'peers'}}){
            $clr .= "    Peer: OESS IP" . $peer->{'local_ip'} . " OESS AS " . $vrf->{'local_asn'} . " Remote AS " . $peer->{'peer_asn'} . " Remote IP " . $peer->{'peer_ip'} . "\n"; 
        }
    }


    my %vars = (
        SUBJECT             => $subject,
        base_url            => $self->{'base_url'},
        vrf                 => $vrf,
        clr                 => $clr,
        from_signature_name => $self->{'from_name'},
        type                => $type,
        reason              => $reason,
        image_base_url      => $self->{'image_base_url'},
        human_time          => $str_date
        );

    my %tmpl_options = ( ABSOLUTE=>1,
                         RELATIVE=>0,
        );
    my $body;

    #get workgroup members
    my $workgroup_members = $self->{'db'}->get_users_in_workgroup(
        workgroup_id => $vrf->{'workgroup'}->{'workgroup_id'}
        );

    foreach my $user ( @{ $workgroup_members } ) {
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
            Subject => $subject,
            Encoding    => 'quoted-printable',
            Timezone => 'UTC',
            Template => {
                html => $self->{'template_path'} . "/notification_vrf.tt.html",
                text => $self->{'template_path'} . "/notification_templates_vrf.tmpl"
            },
            TmplParams => \%vars,
            TmplOptions => \%tmpl_options,
            );


        $message->send( 'smtp', 'localhost' );
    };

    if($@){
        $self->{'log'}->error("Error sending Notification: " . $@);
    }


    my @workgroups_to_notify;
    foreach my $ep (@{$vrf->{'endpoints'}}){
        push(@workgroups_to_notify, $ep->{'workgroup_id'}) if $ep->{'workgroup_id'} ne $vrf->{'workgroup'}->{'workgroup_id'};
    }

    my @full_list;
    foreach my $wg (@workgroups_to_notify){
            #get workgroup members
        my $workgroup_members = $self->{'db'}->get_users_in_workgroup(
            workgroup_id => $wg
            );

        foreach my $user ( @{ $workgroup_members } ) {
            push( @full_list, $user->{'email_address'} );
        }
    }
    
    if(scalar(@full_list > 0)){
        $to_string = join( ",", @full_list );
        
        eval{
            my $message = MIME::Lite::TT::HTML->new(
                From    => $self->{'from_address'},
                To      => $to_string,
                Subject => $subject,
                Encoding    => 'quoted-printable',
                Timezone => 'UTC',
                Template => {
                    html => "$self->{'template_path'}/notification_vrf.tt.html",
                    text => "$self->{'template_path'}/notification_templates_vrf.tmpl"
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

    return 1;
    
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
    my $str_date = $dt->day_name() . ", " . $dt->month_name() . " " . $dt->day() . ", " . $dt->year() . ", at " . $dt->hms() . " UTC";
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

    $self->{'rabbit_config'} = $config->{'rabbitMQ'};
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
    $self->{'db_new'} = OESS::DB->new();
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
	      next;
	  }
          my $interface = $db->get_interface(interface_id =>$interface_id);
	  if(!defined($interface)){
	      $self->{'log'}->error("unable to find an interface with ID: " . $interface_id);
	      next;
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
