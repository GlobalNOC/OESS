#!/usr/bin/perl
#
##----- D-Bus OESS NSI Reservation State Machine
##-----
##----- Handles NSI Reservation Requests
#---------------------------------------------------------------------
#
# Copyright 2015 Trustees of Indiana University
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

package OESS::NSI::Reservation;

$ENV{CRYPT_SSLEAY_CIPHER} = 'ALL';
use strict;
use warnings;

use SOAP::Lite on_action => sub { sprintf '"http://schemas.ogf.org/nsi/2013/12/connection/service/%s"', $_[1]};

use GRNOC::Log;
use GRNOC::Config;
use GRNOC::WebService::Client;

use OESS::NSI::Constant;
use OESS::NSI::Utils;
use DateTime;

use Data::Dumper;

=head2 new

=cut

sub new {
    my $caller = shift;

    my $class = ref($caller);
    $class = $caller if(!$class);

    my $self = {
        'config_file' => undef,
        @_
    };

    bless($self,$class);

    $self->_init();

    return $self;
}

sub _parseTime{
    my $time = shift;
    
    if(!defined($time) || $time eq ''){
        return -1;
    }
    
    log_debug("parsingTime: " . $time);

    #here are some examples
    #2015-08-15T10:30:10.000Z
    #2015-10-22T20:33:00.000-07:00
    $time =~ /(\d\d\d\d)-(\d\d)-(\d\d)T(\d\d)\:(\d\d):(\d\d)(.*)/; #\.\d\d\d(.*)/;

    my $year = $1;
    my $month = $2;
    my $day = $3;
    my $hour = $4;
    my $min = $5;
    my $sec = $6;

    log_debug("Time: " . $year . "-" . $month . "-" . $day . "T" . $hour . ":" . $min);

    my $tz = $7;

    log_debug("TZ: " . $tz);

    #handle the ms if they exist...
    $tz =~ s/\.\d\d\d//g;
    
    if($tz eq 'Z'){
        $tz = "UTC";
    }else{
        $tz =~ s/\://g;
    }

    log_debug("Cleaned TZ: " .$tz);

    my $dt;
    eval{
        $dt = DateTime->new(
            year      => $year,
            month     => $month,
            day       => $day,
            hour      => $hour,
            minute    => $min,
            time_zone => $tz
            );
    };
    warn() if $@;

    log_debug("DateTime object created!");

    return $dt->epoch();
}

=head2 reserve

=cut

sub reserve {
    my ($self, $args) = @_;

    my $connection_id = $args->{'connectionId'};
    my $gri = $args->{'gri'};
    my $description = $args->{'description'};
    my $start_time = _parseTime($args->{'criteria'}->{'schedule'}->{'startTime'});
    my $end_time = _parseTime($args->{'criteria'}->{'schedule'}->{'endTime'});
    my $source_stp = $args->{'criteria'}->{'p2ps'}->{'sourceSTP'};
    my $dest_stp = $args->{'criteria'}->{'p2ps'}->{'destSTP'};
    my $directionality = $args->{'criteria'}->{'p2ps'}->{'directionality'};
    my $capacity = $args->{'criteria'}->{'p2ps'}->{'capacity'};
    my $reply_to = $args->{'header'}->{'replyTo'};

    log_info("new reservation request: Requester " . $args->{'header'}->{'requesterNSA'} . " sourceSTP: " . $source_stp . " destSTP: " . $dest_stp . " description: " . $description . " gri: " . $gri);

    if(!$description || !$source_stp || !$dest_stp || !$reply_to){
        log_info("reservation request missing some parameters!");
        push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_FAIL, connection_id => 9999999, args => $args});
        return OESS::NSI::Constant::MISSING_REQUEST_PARAMETERS;
    }
    
    my $ep1 = $self->get_endpoint(stp => $source_stp);
    if(!defined($ep1)){
        log_error("Unable to find sourceSTP: " . $source_stp . " in OESS");
        $args->{'fail_text'} = "Unable to parse source STP";
        push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_FAIL, connection_id => 9999999, args => $args});
        return OESS::NSI::Constant::RESERVATION_FAIL;
    }
    my $ep2 = $self->get_endpoint(stp => $dest_stp);
    if(!defined($ep2)){
        log_error("Unable to find destSTP: " . $dest_stp . " in OESS");
        $args->{'fail_text'} = "Unable to parse dest STP";
        push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_FAIL, connection_id => 9999999, args => $args});
        return OESS::NSI::Constant::RESERVATION_FAIL;
    }

    if(!$self->validate_endpoint($ep1)){
        log_error("sourceSTP $source_stp is not allowed for NSI");
        $args->{'fail_text'} = "Source STP $source_stp not allowed for NSI workgroup";
        push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_FAIL, connection_id => 9999999, args => $args});
        return OESS::NSI::Constant::RESERVATION_FAIL;
    }

    if(!$self->validate_endpoint($ep2)){
        log_error("destSTP $dest_stp is not allowed for NSI");
        $args->{'fail_text'} = "destSTP $dest_stp is not allowed for NSI workgroup";
        push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_FAIL, connection_id => 9999999, args => $args});
        return OESS::NSI::Constant::RESERVATION_FAIL;
    }
    

    my $primary_path = $self->get_shortest_path($ep1, $ep2, []);
    if(!defined($primary_path)){
        log_error("Unable to connect $source_stp and $dest_stp");
        $args->{'fail_text'} = "no path exists connecting both source and destination STP";
        push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_FAIL, connection_id => 9999999, args => $args});
        return OESS::NSI::Constant::RESERVATION_FAIL;
    }
    
    my $backup_path = $self->get_shortest_path($ep1, $ep2, $primary_path);

    $self->{'websvc'}->set_url($self->{'websvc_location'} . "provisioning.cgi");
    
    my $res = $self->{'websvc'}->foo( action => "provision_circuit",
				      state  => 'reserved',
                                      workgroup_id => $self->{'workgroup_id'},
                                      external_identifier => $gri,
                                      description => $description,
                                      bandwidth => $capacity,
                                      provision_time => $start_time,
                                      remove_time => $end_time,
                                      link => $primary_path,
                                      backup_link => $backup_path,
                                      remote_url => $args->{'header'}->{'replyTo'},
                                      remote_requester => $args->{'header'}->{'requesterNSA'},
                                      node => [$ep1->{'node'}, $ep2->{'node'}],
                                      interface => [$ep1->{'port'}, $ep2->{'port'}],
                                      tag => [$ep1->{'vlan'}, $ep2->{'vlan'}]);
    
    if(defined($res->{'results'}) && $res->{'results'}->{'success'} == 1){
        log_info("Successfully created reservation, connectionId: " . $res->{'results'}->{'circuit_id'});
        push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_SUCCESS, connection_id => $res->{'results'}->{'circuit_id'}, args => $args});
        return $res->{'results'}->{'circuit_id'};
    }else{
        log_error("Unable to reserve circuit: " . $res->{'error'});
        $args->{'fail_text'} = "Error creating reservation record: " . $res->{'error'};
        push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_FAIL, connection_id => 9999999, args => $args});
        return OESS::NSI::Constant::RESERVATION_FAIL;
    }
}

=head2 reserveAbort

=cut

sub reserveAbort{
    my ($self, $args) = @_;

    my $connection_id = $args->{'connectionId'};

    if(!defined($connection_id) || $connection_id eq ''){
        return OESS::NSI::Constant::MISSING_REQUEST_PARAMETERS;
    }
    
    push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::DO_RESERVE_ABORT, args => $args});
    return OESS::NSI::Constant::SUCCESS;
}

sub _do_reserve_abort{
    my ($self, $data) = @_;

    my $connection_id = $data->{'connectionId'};
    
    log_info("reservationAbort: connectionId: " . $connection_id);

    $self->{'websvc'}->set_url($self->{'websvc_location'} . "/provisioning.cgi");
    my $res = $self->{'websvc'}->foo( action => "remove_circuit",
                                      circuit_id => $connection_id,
                                      workgroup_id => $self->{'workgroup_id'},
                                      remove_time => -1);
    
    if(defined($res) && defined($res->{'results'})){
        log_info("reservationAbort successfull: connectionId: " . $connection_id);
        my $soap = OESS::NSI::Utils::build_client( proxy => $data->{'header'}->{'replyTo'}, ssl => $self->{'ssl'});
        my $nsiheader = OESS::NSI::Utils::build_header($data->{'header'});
        my $soap_response;
        eval{
            $soap_response = $soap->reserveAbortConfirmed($nsiheader, SOAP::Data->name(connectionId => $connection_id)->type(''));
        };
        log_debug("Response: " . Data::Dumper::Dumper($soap_response));
        log_error("Error sending SOAP confirmation: " . Data::Dumper::Dumper($soap_response) . " " . Data::Dumper::Dumper($@)) if defined($@);
        return;
    }

    log_error("Unable to remove circuit: " . $res->{'error'});
    return OESS::NSI::Constant::ERROR;

}

=head2 get_endpoint

=cut


sub get_endpoint{
    my $self = shift;
    my %params = @_;

    if(!defined($params{'stp'})){
        log_error("get_endpoint: stp is undefined");
        return;
    }

    my $stp = $params{'stp'};
    #example URN urn:ogf:network:nsi.nddi-dev.bldc.net.internet2.edu:2013::s1:1-0:+
    my @parts = split(':',$stp);
    my $domain = $parts[3];
    my $node = $parts[6];
    my $interface = $parts[7];
    my $link = $parts[8];
    
    $link =~ /\?vlan=(\d+)/;
    my $vlan = $1;

    if(!defined($domain) || !defined($node) || !defined($interface) || !defined($vlan)){
        log_error("Error processing URN $stp, missing some important pieces");
        return;
    }

    return { node => $node, port => $interface, vlan => $vlan, domain => $domain };
        
}

=head2 validate_endpoint

=cut

sub validate_endpoint{
    my $self = shift;
    my $ep = shift;
    
    #need to verify this is part of our network and actually exists and that we have permission!

    $self->{'websvc'}->set_url($self->{'websvc_location'} . "data.cgi");

    log_debug("Checking validity of EP: " . Data::Dumper::Dumper($ep));
    
    log_debug("requesting all resources for NSI workgroup");
    my $res = $self->{'websvc'}->foo( action => "get_all_resources_for_workgroup",
                                      workgroup_id => $self->{'workgroup_id'});


    if(defined($res) && defined($res->{'results'})){        
        foreach my $resource (@{$res->{'results'}}){
            if($resource->{'node_name'} eq $ep->{'node'}){
                if($resource->{'interface_name'} eq $ep->{'port'}){
                    log_debug("Found interface for requested EP, requesting VLAN availability");
                    #made it this far!
                    my $valid_tag = $self->{'websvc'}->foo( action => "is_vlan_tag_available",
                                                            interface => $ep->{'port'},
                                                            node => $ep->{'node'},
                                                            vlan => $ep->{'vlan'},
							    workgroup_id => $self->{'workgroup_id'});
                    
                    log_debug("Results from is valid tag: " . Data::Dumper::Dumper($valid_tag));
                    if(defined($valid_tag) && $valid_tag->{'results'}){
                        log_debug("results from is_vlan_tag_available: " . Data::Dumper::Dumper($valid_tag->{'results'}));
			if($valid_tag->{'results'}->[0]->{'available'} == 1){
                            return 1;
                        }
                    }
                    return 0;

                }
            }
        }
    }else{
        log_error("Unable to fetch workgroup resources" . Data::Dumper::Dumper($res));
        return 0;
    }
    log_error("not a valid endpoint, or not allowed via NSI workgroup");
    return 0;
    
    

}

=head2 get_shortest_path

=cut

sub get_shortest_path{
    my $self = shift;
    my $ep1 = shift;
    my $ep2 = shift;
    my $links = shift;

    $self->{'websvc'}->set_url($self->{'websvc_location'} . "data.cgi");
    my $shortest_path = $self->{'websvc'}->foo( action => "get_shortest_path",
                                                node => [$ep1->{'node'},$ep2->{'node'}],
                                                link => $links);
    
    log_debug("Shortest path: " . Data::Dumper::Dumper($shortest_path));
    if(defined($shortest_path) && defined($shortest_path->{'results'})){
	my @links = ();
	foreach my $link (@{$shortest_path->{'results'}}){
	    push(@links,$link->{'link'});
	}
	return \@links;
    }
    log_error("unable to find path");
    return;
}

=head2 reserveCommit

=cut

sub reserveCommit{
    my ($self, $args) = @_;
    
    log_info("reserveCommit: connectionId: " . $args->{'connectionId'});

    push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_COMMIT_CONFIRMED, args => $args});

}

=head2 process_queue

=cut

sub process_queue {
    my ($self) = @_;

    log_debug("Processing Reservation Queue");
    while(my $message = shift(@{$self->{'reservation_queue'}})){
        my $type = $message->{'type'};

        if($type == OESS::NSI::Constant::RESERVATION_SUCCESS){
            log_debug("Handling Reservation Success Message");
            my $connection_id = $message->{'connection_id'};
            $self->_reserve_confirmed($message->{'args'}, $connection_id);
            next;
        }elsif($type == OESS::NSI::Constant::RESERVATION_FAIL){
            log_debug("Handling Reservation Fail Message");
            $self->_reserve_failed($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::RESERVATION_COMMIT_CONFIRMED){
            log_debug("handling reservation commit success");
            $self->_reserve_commit_confirmed($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::DO_RESERVE_ABORT,){
            log_debug("handling reservation abort");
            $self->_do_reserve_abort($message->{'args'});
            next;            
        }else{
            log_error("Unknown message type: " . $type);
            next;
        }
    }
}

sub _build_p2ps{
    my $p2ps = shift;
    
    return SOAP::Data->name( p2ps => \SOAP::Data->value( SOAP::Data->name( capacity => $p2ps->{'capacity'} )->type(''),
                                                         SOAP::Data->name( directionality => $p2ps->{'directionality'} )->type(''),
                                                         SOAP::Data->name( sourceSTP => $p2ps->{'sourceSTP'} )->type(''),
                                                         SOAP::Data->name( destSTP => $p2ps->{'destSTP'} )->type('')))->uri('http://schemas.ogf.org/nsi/2013/12/services/point2point');
    
}

sub _build_schedule{
    my $schedule = shift;
    if($schedule->{'startTime'} ne ''){
        return SOAP::Data->name( schedule => \SOAP::Data->value( SOAP::Data->name( startTime => $schedule->{'startTime'})->type(''),
                                                                 SOAP::Data->name( endTime => $schedule->{'endTime'})->type('')));
    }

    return SOAP::Data->name( schedule => \SOAP::Data->value( SOAP::Data->name( endTime => $schedule->{'endTime'} )->type('')));
}

sub _build_criteria{
    my $criteria = shift;
    
    return SOAP::Data->name(criteria => 
                            \SOAP::Data->value( _build_schedule( $criteria->{'schedule'}),
                                                SOAP::Data->name( serviceType => $criteria->{'serviceType'}->{'type'})->type(''),
                                                _build_p2ps( $criteria->{'p2ps'} )
                            ))->attr({ version => $criteria->{'version'}->{'version'}++});
    

}

sub _reserve_confirmed {
    my ($self, $data, $connection_id) = @_;

    log_debug("Sending Reservation Confirmation");

    my $soap = OESS::NSI::Utils::build_client( proxy => $data->{'header'}->{'replyTo'}, ssl => $self->{'ssl'});

    my $nsiheader = OESS::NSI::Utils::build_header($data->{'header'});

    eval{
        my $soap_response = $soap->reserveConfirmed($nsiheader, SOAP::Data->name(connectionId => $connection_id)->type(''),
                                                    SOAP::Data->name(globalReservationId => $data->{'globalReservationId'})->type(''),
                                                    SOAP::Data->name(description => $data->{'description'})->type(''),
                                                    _build_criteria($data->{'criteria'}) 
            );
        
    };
    log_error("Error sending reserveConfirmed message: " .Data::Dumper::Dumper($@)) if $@;

}

sub _reserve_commit_confirmed{
    my ($self, $data) = @_;

    my $soap = OESS::NSI::Utils::build_client( proxy =>$data->{'header'}->{'replyTo'},ssl => $self->{'ssl'});

    my $nsiheader = OESS::NSI::Utils::build_header($data->{'header'});
    eval{
        my $soap_response = $soap->reserveCommitConfirmed($nsiheader, SOAP::Data->name(connectionId => $data->{'connectionId'})->type(''));
    };
    log_error("Error sending reserveCommitConfirmed message: " .Data::Dumper::Dumper($@)) if $@;
}

sub _build_service_exception{
    my $self = shift;
    my %params = @_;
    
    my $exception = SOAP::Data->name( serviceException => \SOAP::Data->value(
                                          SOAP::Data->name( nsaId => $params{'nsaid'})->type(''),
                                          SOAP::Data->name( connectionId => $params{'connectionId'})->type(''),
                                          SOAP::Data->name( serviceType => $params{'serviceType'}->{'type'})->type(''),
                                          SOAP::Data->name( errorId => $params{'errorId'})->type(''),
                                          SOAP::Data->name( text => $params{'text'})->type('')));
    
    return $exception;
}

sub _build_connection_states{
    my $self = shift;
    my %params = @_;
    
    my $connection_state = SOAP::Data->name( connectionStates => \SOAP::Data->value(
                                                 SOAP::Data->name( reservationState => $params{'reservationState'})->type(''),
                                                 SOAP::Data->name( provisionState => $params{'provisionState'})->type(''),
                                                 SOAP::Data->name( lifecycleState => $params{'lifecycleState'})->type(''),
                                                 SOAP::Data->name( dataPlaneStatus => \SOAP::Data->value( SOAP::Data->name( active => $params{'dataPlaneStatus'}->{'active'})->type(''),
                                                                                                         SOAP::Data->name( version => $params{'dataPlaneStatus'}->{'version'})->type(''),
                                                                                                         SOAP::Data->name( versionConsistent => $params{'dataPlaneStatus'}->{'versionConsistent'})->type('')))));
    return $connection_state;

}

sub _reserve_failed {
    my ($self, $data) = @_;

    log_debug("Sending reserve Failed!\n");

    log_error("Error reserving circuit... sending reserveFailed message");

    my $soap = OESS::NSI::Utils::build_client( proxy =>$data->{'header'}->{'replyTo'},ssl => $self->{'ssl'});
    my $nsiheader = OESS::NSI::Utils::build_header($data->{'header'});

    eval{

        my $soap_response = $soap->reserveFailed($nsiheader, SOAP::Data->name(connectionId => $data->{'connectionId'})->type(''),
                                                 $self->_build_service_exception( nsaId => $data->{'header'}->{'providerNSI'},
                                                                                  connectionId => $data->{'connectionId'},
                                                                                  serviceType => $data->{'criteria'}->{'serviceType'},
                                                                                  errorId => 999,
                                                                                  text => $data->{'fail_text'}),
                                                 $self->_build_connection_states( reservationState => 'ReserveFailed',
                                                                                  provisionState => 'released',
                                                                                  lifecycleState => 'Created',
                                                                                  dataPlaneStatus => { active => 'false',
                                                                                                       version => $data->{'criteria'}->{'version'}->{'version'},
                                                                                                       versionConsistent => 'true'}));

    };
    log_error("Error sending reserveFailed: " . Data::Dumper::Dumper($@)) if $@;
}

sub _init {
    my ($self) = @_;

    log_debug("Creating new Config object from $self->{'config_file'}");
    my $config = new GRNOC::Config(
        'config_file' => $self->{'config_file'},
        'force_array' => 0
        );

    $self->{'config'} = $config;

    log_debug("Creating new WebService Client object");
    my $websvc = new GRNOC::WebService::Client(
        'cookieJar' => '/tmp/oess-nsi-cookies.dat',
        'debug' => $self->{'debug'}
        );

    $self->{'websvc'} = $websvc;

    $self->{'websvc_user'}     = $self->{'config'}->get('/config/oess-service/@username');
    $self->{'websvc_pass'}     = $self->{'config'}->get('/config/oess-service/@password');
    $self->{'websvc_realm'}    = $self->{'config'}->get('/config/oess-service/@realm');
    $self->{'websvc_location'} = $self->{'config'}->get('/config/oess-service/@web-service');

    $self->{'websvc'}->set_credentials(
        'uid' => $self->{'websvc_user'},
        'passwd' => $self->{'websvc_pass'},
	'realm' => $self->{'websvc_realm'}
        );

    $self->{'ssl'} = $self->{'config'}->get('/config/ssl');
    if(defined($self->{'ssl'}->{'enabled'}) && $self->{'ssl'}->{'enabled'} ne '' && $self->{'ssl'}->{'enabled'} eq 'true'){
        $self->{'ssl'}->{'enabled'} = 1;
    }

    $self->{'workgroup_id'} = $self->{'config'}->get('/config/oess-service/@workgroup-id');

    $self->{'reservation_queue'} = [];
}

sub _release_confirmed{
    my ($self, $data) = @_;

    log_info(" releaseConfirmed: connectionId" . $data->{'connectionId'});

    my $soap = OESS::NSI::Utils::build_client( proxy =>$data->{'header'}->{'replyTo'},ssl => $self->{'ssl'});

    my $nsiheader = OESS::NSI::Utils::build_header($data->{'header'});
    eval{
        my $soap_response = $soap->releaseConfirmed($nsiheader, SOAP::Data->name(connectionId => $data->{'connectionId'})->type(''));
    };
    log_error("Error sending releaseConfirmed: " . Data::Dumper::Dumper($@)) if $@;
}

1;
