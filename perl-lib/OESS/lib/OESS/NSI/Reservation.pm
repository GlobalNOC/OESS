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
use OESS::Database;
use JSON::XS;
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

    $self->{'log'} = GRNOC::Log->get_logger("OESS.NSI.Reservation");
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
    

#    my $primary_path = $self->get_shortest_path($ep1, $ep2, []);
#    if(!defined($primary_path)){
#        log_error("Unable to connect $source_stp and $dest_stp");
#        $args->{'fail_text'} = "no path exists connecting both source and destination STP";
#        push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_FAIL, connection_id => 9999999, args => $args});
#        return OESS::NSI::Constant::RESERVATION_FAIL;
#    }
#    
#    my $backup_path = $self->get_shortest_path($ep1, $ep2, $primary_path);

    $self->{'websvc'}->set_url($self->{'websvc_location'} . "circuit.cgi");

    #warn Dumper($ep1);
    #warn Dumper($ep2);
    
    my $endpoint1 = {'node' => $ep1->{'node'}, interface => $ep1->{'port'}, tag => $ep1->{'tags'}->[0]};
    my $endpoint2 = {'node' => $ep2->{'node'}, interface => $ep2->{'port'}, tag => $ep2->{'tags'}->[0]};
    
    my $res = $self->{'websvc'}->provision(
	status  => 'reserved',
	workgroup_id => $self->{'workgroup_id'},
	external_identifier => $gri,
	description => $description,
	bandwidth => $capacity,
	provision_time => $start_time,
	remove_time => $end_time,
	remote_url => $args->{'header'}->{'replyTo'},
	remote_requester => $args->{'header'}->{'requesterNSA'},
	endpoint => [JSON::to_json($endpoint1), JSON::to_json($endpoint2)]);
    
    log_error("Results of provision: " . Data::Dumper::Dumper($res));

    if(defined($res->{'success'} == 1)){
        log_info("Successfully created reservation, connectionId: " . $res->{'circuit_id'});
        $args->{'connection_id'} = $res->{'circuit_id'};
        $args->{'criteria'}->{'p2ps'}->{'sourceSTP'} = $self->build_stp($ep1);
        $args->{'criteria'}->{'p2ps'}->{'destSTP'} = $self->build_stp($ep2);
        push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_SUCCESS, connection_id => $res->{'circuit_id'}, args => $args});
        push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_TIMEOUT, connection_id => $res->{'circuit_id'}, args => $args, time => time() + OESS::NSI::Constant::RESERVATION_TIMEOUT_SEC});
        return $res->{'circuit_id'};
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

    $self->{'websvc'}->set_url($self->{'websvc_location'} . "/circuit.cgi");
    my $res = $self->{'websvc'}->remove(
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

=head2 build_stp

=cut

sub build_stp{
    my $self = shift;
    my $ep = shift;
    #example urn:ogf:network:nsi.nddi-dev.bldc.net.internet2.edu:2013::s1:1-0:+

    my $str = "urn:ogf:network:nsi.";
    $str .= $self->{'db'}->get_local_domain_name();
    $str .= ":2013::" . $ep->{'node'} . ":" . $ep->{'port'} . ":" . $ep->{'link'} . "?vlan=" . $ep->{'tags'}->[0];
    return $str;
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
    
    $link =~ /(.*)\?vlan=(.*)/;
    $link = $1;
    my $vlan = $2;

    #lots of options here
    #1-2000,3000-4000
    my @vlans = split(',',$vlan);
    my @tags;

    foreach my $vlan (@vlans){
        if($vlan =~ /(\d+)-(\d+)/){
            my $start = $1;
            my $end = $2;

            if($end > 4095){
                log_error("VLAN tag " . $end . " is > max VLAN tag 4095");
                return;
            }
            for(my $i=$start;$i<=$end;$i++){
                push(@tags,int($i));
            }
        }else{
            log_error("VLAN: " . $vlan);
            push(@tags, int($vlan));
        }
    }

    log_debug("Tags: " . Data::Dumper::Dumper(@tags));

    if(!defined($domain) || !defined($node) || !defined($interface) || scalar(@tags) < 0){
        log_error("Error processing URN $stp, missing some important pieces");
        return;
    }

    return { node => $node, port => $interface, tags => \@tags, domain => $domain, link => $link };
        
}

=head2 validate_endpoint

=cut

sub validate_endpoint{
    my $self = shift;
    my $ep = shift;
    
    #need to verify this is part of our network and actually exists and that we have permission!
    $self->{'log'}->info("Checking validity of port $ep->{'port'} on $ep->{'node'}." . Dumper($ep));

    my $url = $self->{'websvc_location'} . "interface.cgi";
    $self->{'websvc'}->set_url($url);
    #finding node and interface
    
    $self->{'log'}->debug("Requesting all available VLANs for NSI workgroup for interface $ep->{'port'} from $url" . Dumper($ep));

    my $interface = $self->{'websvc'}->get_interfaces(node => $ep->{'node'}, name => $ep->{'port'});
    $self->{'log'}->error(Dumper($interface));
    
    if(defined($interface)){
	if(defined($interface->{'results'}) && defined($interface->{'results'}->[0])){
	    $self->{'log'}->error("Interface results: " . Dumper($interface));
	    $self->{'websvc'}->{'debug'} = 1;
	    foreach my $tag (@{$ep->{'tags'}}){
		my $is_vlan_available = $self->{'websvc'}->is_vlan_available( interface_id => $interface->{'results'}->[0]->{'interface_id'}, workgroup_id => $self->{'workgroup_id'}, vlan => $tag);
		$self->{'log'}->error("available: " . Dumper($is_vlan_available));
		if(defined($is_vlan_available) && defined($is_vlan_available->{'results'})){	
		    if(!$is_vlan_available->{'results'}->{'allowed'}){
			return 0;
		    }
		}else{
		    return 0;
		}
	    }
	    return 1;
	}else{
	    $self->{'log'}->error("Error fetching interface " . $ep->{'port'} . " on node: " . $ep->{'node'});
	    $self->{'log'}->error($interface->{'error'});
	    return 0;
	}
    }
       
    $self->{'log'}->error("not a valid endpoint, or not allowed via NSI workgroup: " . Dumper($interface));
    return 0;
}

=head2 reserveCommit

=cut

sub reserveCommit{
    my ($self, $args) = @_;
    
    log_info("reserveCommit: connectionId: " . $args->{'connectionId'});

    my $i=0;
    foreach my $event (@{$self->{'reservation_queue'}}){
        if($event->{'type'} == OESS::NSI::Constant::RESERVATION_TIMEOUT && $event->{'connection_id'} == $args->{'connectionId'}){
            my $res = splice(@{$self->{'reservation_queue'}}, $i, 1);
            push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_COMMIT_CONFIRMED, args => $args});
	    return OESS::NSI::Constant::SUCCESS;
	}
        $i++;
    }

    push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_COMMIT_FAILED, args => $args});

}

=head2 process_queue

=cut

sub process_queue {
    my ($self) = @_;

    log_debug("Processing Reservation Queue");

    my @still_needs_to_be_done;

    while(my $message = shift(@{$self->{'reservation_queue'}})){
        my $type = $message->{'type'};
        #warn Data::Dumper::Dumper($message);
        #this is now a scheduler... skip the action if it has a time and we aren't past it yet
        if(defined($message->{'time'}) && time() < $message->{'time'}){            
            #log_error("TIME: " . $message->{'time'} . " vs. " . time());
            push(@still_needs_to_be_done, $message);
            next;
        }
        
        #ok pull it off the array
        

        if($type == OESS::NSI::Constant::RESERVATION_SUCCESS){
            log_debug("Handling Reservation Success Message");
            my $connection_id = $message->{'connection_id'};
            $self->_reserve_confirmed($message->{'args'}, $connection_id);
            next;
        }elsif($type == OESS::NSI::Constant::RESERVATION_FAIL){
            log_debug("Handling Reservation Fail Message");
            $self->_reserve_failed($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::RESERVATION_TIMEOUT){
            log_info("Reservation Timeout: " . $message->{'connection_id'});
            $self->_reserve_timeout($message->{'args'});        
        }elsif($type == OESS::NSI::Constant::RESERVATION_COMMIT_CONFIRMED){
            log_debug("handling reservation commit success");
            $self->_reserve_commit_confirmed($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::RESERVATION_COMMIT_FAILED){
            log_debug("handling reservation commit failed");
            $self->_reserve_commit_failed($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::DO_RESERVE_ABORT){
            log_debug("handling reservation abort");
            $self->_do_reserve_abort($message->{'args'});
            next;            
        }else{
            log_error("Unknown message type: " . $type);
            next;
        }
    }

    #anything that still needs to be done is pushed back onto the stack
    foreach my $event (@still_needs_to_be_done){
        push(@{$self->{'reservation_queue'}}, $event);
    }

}

sub _reserve_commit_failed{
    my ($self, $data) = @_;

    
    log_error("Error commiting reservation");
    
    my $soap = OESS::NSI::Utils::build_client( proxy => $data->{'header'}->{'replyTo'}, ssl => $self->{'ssl'});
    my $nsiheader = OESS::NSI::Utils::build_header($data->{'header'});

    eval{
        my $soap_response = $soap->reserveCommitFailed($nsiheader, SOAP::Data->name(connectionId => $data->{'connection_id'})->type(''),
                                                       $self->_build_connection_states( reservationState => 'ReserveFailed',
                                                                                        provisionState => 'released',
                                                                                        lifecycleState => 'Created',
                                                                                        dataPlaneStatus => { active => 'false',
                                                                                                             version => $data->{'criteria'}->{'version'}->{'version'},
                                                                                                             versionConsistent => 'true'}),
                                                       $self->_build_service_exception( nsaId => $data->{'header'}->{'providerNSI'},
                                                                                        connectionId => $data->{'connectionId'},
                                                                                        serviceType => $data->{'criteria'}->{'serviceType'},
                                                                                        errorId => 999,
                                                                                        text => "reservation has already expired!"));
    };
    log_error("Error sending reserveCommitFailed message: " . Data::Dumper::Dumper($@)) if $@;
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

    my $start;
    my $end;

    if (defined $schedule->{'startTime'} && $schedule->{'startTime'} ne '') {
        $start = SOAP::Data->name(startTime => $schedule->{'startTime'})->type('');
    }

    if (defined $schedule->{'endTime'} && $schedule->{'endTime'} ne '') {
        $end = SOAP::Data->name(endTime => $schedule->{'endTime'})->type('');
    }

    if (defined $start && defined $end) {
        return SOAP::Data->name(schedule => \SOAP::Data->value($start, $end));
    } elsif (defined $start) {
        return SOAP::Data->name(schedule => \SOAP::Data->value($start));
    } elsif (defined $end) {
        return SOAP::Data->name(schedule => \SOAP::Data->value($end));
    } else {
        return SOAP::Data->name(schedule => \SOAP::Data->value());
    }
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

    $self->{'db'} = OESS::Database->new();

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

sub _reserve_timeout{
    my ($self, $data) = @_;
    
    $self->{'websvc'}->set_url($self->{'websvc_location'} . "circuit.cgi");

    my $res = $self->{'websvc'}->remove(
                                      circuit_id => $data->{'connection_id'},
                                      workgroup_id => $self->{'workgroup_id'});


    my $soap = OESS::NSI::Utils::build_client( proxy =>$data->{'header'}->{'replyTo'},ssl => $self->{'ssl'});
    my $nsiheader = OESS::NSI::Utils::build_header($data->{'header'});
    eval{
        my $soap_response = $soap->reserveTimeout($nsiheader, SOAP::Data->name( connectionId => $data->{'connection_id'})->type(''),
                                                  SOAP::Data->name( notificationId => 0)->type(''),
                                                  SOAP::Data->name( timeStamp => _timestampNow() )->type(''),
                                                  SOAP::Data->name( originatingConnectionId => $data->{'connection_id'})->type(''),
                                                  SOAP::Data->name( originatingNSA => $data->{'header'}->{'providerNSA'})->type(''));
    };
    log_error("Error sending reserveTimeout: " . Data::Dumper::Dumper($@)) if $@;
        
}

sub _timestampNow{

    my $dt = DateTime->now();
    return $dt->strftime( "%F" ) . "T" . $dt->strftime( "%T" ) . "Z";

}

1;
