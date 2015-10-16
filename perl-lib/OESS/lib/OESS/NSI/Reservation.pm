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

use strict;
use warnings;

use SOAP::Lite on_action => sub { sprintf '"http://schemas.ogf.org/nsi/2013/12/connection/service/%s"', $_[1]};

use GRNOC::Log;
use GRNOC::Config;
use GRNOC::WebService::Client;

use OESS::NSI::Constant;

use Data::Dumper;

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

sub reserve {
    my ($self, $args) = @_;

    my $connection_id = $args->{'connectionId'};
    my $gri = $args->{'gri'};
    my $description = $args->{'description'};
    my $start_time = $args->{'criteria'}->{'schedule'}->{'startTime'};
    my $end_time = $args->{'criteria'}->{'schedule'}->{'endTime'};
    my $source_stp = $args->{'criteria'}->{'p2ps'}->{'sourceSTP'};
    my $dest_stp = $args->{'criteria'}->{'p2ps'}->{'destSTP'};
    my $directionality = $args->{'criteria'}->{'p2ps'}->{'directionality'};
    my $capacity = $args->{'criteria'}->{'p2ps'}->{'capacity'};
    my $reply_to = $args->{'header'}->{'replyTo'};
    
    warn "IN RESERVE!\n";

    if(!$description || !$source_stp || !$dest_stp || !$reply_to){
        return OESS::NSI::Constant::MISSING_REQUEST_PARAMETERS;
    }
    
    my $ep1 = $self->get_endpoint(stp => $source_stp);
    if(!defined($ep1)){
        log_error("Unable to find sourceSTP: " . $source_stp . " in OESS");
        return OESS::NSI::Constant::RESERVATION_FAIL;
    }
    my $ep2 = $self->get_endpoint(stp => $dest_stp);
    if(!defined($ep2)){
        log_error("Unable to find destSTP: " . $dest_stp . " in OESS");
        return OESS::NSI::Constant::RESERVATION_FAIL;
    }

    if(!$self->validate_endpoint($ep1)){
        log_error("sourceSTP is not allowed for NSI");
        return OESS::NSI::Constant::RESERVATION_FAIL;
    }

    if(!$self->validate_endpoint($ep2)){
        log_error("destSTP is not allowed for NSI");
        return OESS::NSI::Constant::RESERVATION_FAIL;
    }
    

    my $primary_path = $self->get_shortest_path($ep1, $ep2, []);
    if(!defined($primary_path)){
        log_error("Unable to connect the source and dest STPs");
        return OESS::NSI::Constant::RESERVATION_FAIL;
    }
    
    my $backup_path = $self->get_shortest_path($ep1, $ep2, $primary_path);
    
    $self->{'websvc'}->set_url($self->{'websvc_location'} . "provisioning.cgi");
    
    my $res = $self->{'websvc'}->foo( action => "provision_circuit",
				      status => 'reserved',
                                      workgroup_id => $self->{'workgroup_id'},
                                      external_identifier => $gri,
                                      description => $description,
                                      bandwidth => $capacity,
                                      provision_time => $start_time,
                                      remove_time => $end_time,
                                      link => $primary_path,
                                      backup_link => $backup_path,
                                      node => [$ep1->{'node'}, $ep2->{'node'}],
                                      interface => [$ep1->{'port'}, $ep2->{'port'}],
                                      tag => [$ep1->{'vlan'}, $ep2->{'vlan'}]);
    
    if(defined($res->{'results'}) && $res->{'results'}->{'success'} == 1){
        push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_SUCCESS, connection_id => $res->{'results'}->{'circuit_id'}, args => $args});
        return $res->{'results'}->{'circuit_id'};
    }else{
        log_error("Unable to reserve circuit: " . $res->{'error'});
        return OESS::NSI::Constant::RESERVATION_FAIL;
    }
}

sub get_endpoint{
    my $self = shift;
    my %params = @_;

    if(!defined($params{'stp'})){
        return;
    }

    my $stp = $params{'stp'};
    #example URN urn:ogf:network:domain=al2s.net.internet2.edu:node=sdn-sw.elpa.net.internet2.edu:port=eth1/2:link=I2-DENV-ELPA-100GE-07748
    my @parts = split(':',$stp);
    my $domain = $parts[3];
    my $node = $parts[4];
    my $interface = $parts[5];
    my $link = $parts[6];
    
    $domain =~ /domain\=(.*)/;
    $domain = $1;
    $node =~ /node\=(.*)/;
    $node = $1;
    $interface =~ /port\=(.*)/;
    $interface = $1;
    $link =~ /\?vlan=(\d+)/;
    my $vlan = $1;

    if(!defined($domain) || !defined($node) || !defined($interface) || !defined($vlan)){
        log_error("Error processing URN, missing some important pieces");
        return;
    }

    return { node => $node, port => $interface, vlan => $vlan, domain => $domain };
        
}

sub validate_endpoint{
    my $self = shift;
    my $ep = shift;
    
    #need to verify this is part of our network and actually exists and that we have permission!

    $self->{'websvc'}->set_url($self->{'websvc_location'} . "data.cgi");

    print STDOUT Data::Dumper::Dumper($ep);
    
    my $res = $self->{'websvc'}->foo( action => "get_all_resources_for_workgroup",
                                      workgroup_id => $self->{'workgroup_id'});

    if(defined($res) && defined($res->{'results'})){
        foreach my $resource (@{$res->{'results'}}){
            if($resource->{'node_name'} eq $ep->{'node'}){
                if($resource->{'interface_name'} eq $ep->{'port'}){
                    
                    #made it this far!
                    my $valid_tag = $self->{'websvc'}->foo( action => "is_vlan_tag_available",
                                                            interface => $ep->{'port'},
                                                            node => $ep->{'node'},
                                                            vlan => $ep->{'vlan'},
							    workgroup_id => $self->{'workgroup_id'});
                    if(defined($valid_tag) && $valid_tag->{'results'}){
                        warn Data::Dumper::Dumper($valid_tag);
			if($valid_tag->{'results'}->[0]->{'available'} == 1){
                            return 1;
                        }
                    }
                    return;

                }
            }
        }
    }else{
        log_error("Unable to fetch workgroup resources");
        return;
    }
    
    

}

sub get_shortest_path{
    my $self = shift;
    my $ep1 = shift;
    my $ep2 = shift;
    my $links = shift;

    $self->{'websvc'}->set_url($self->{'websvc_location'} . "data.cgi");
    my $shortest_path = $self->{'websvc'}->foo( action => "get_shortest_path",
                                                node => [$ep1->{'node'},$ep2->{'node'}],
                                                link => $links);
    
    warn Data::Dumper::Dumper($shortest_path);
    if(defined($shortest_path) && defined($shortest_path->{'results'})){
	my @links = ();
	foreach my $link (@{$shortest_path->{'results'}}){
	    push(@links,$link->{'link'});
	}
	return \@links;
    }

    return;
                                                
    
}

sub reserveCommit{
    my ($self, $args) = @_;
    
    push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_COMMIT_CONFIRMED, connection_id => 100, args => $args});

}

sub process_queue {
    my ($self) = @_;

    log_debug("Processing Reservation Queue.");
    warn "Reservation Queue1: " . Data::Dumper::Dumper($self->{'reservation_queue'});
    while(my $message = shift(@{$self->{'reservation_queue'}})){
        my $type = $message->{'type'};

        if($type == OESS::NSI::Constant::RESERVATION_SUCCESS){
            log_debug("Handling Reservation Success Message");

            my $connection_id = $message->{'connection_id'};

            $self->_reserve_confirmed($message->{'args'}, $connection_id);
            next;
        }
        elsif($type == OESS::NSI::Constant::RESERVATION_FAIL){
            log_debug("Handling Reservation Fail Message");

            $self->_reserve_failed($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::RESERVATION_COMMIT_CONFIRMED){
            log_debug("handling reservation commit success");
            
            $self->_reserve_commit_confirmed($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::RELEASE_SUCCESS){
            log_debug("handling release success");

            $self->_release_confirmed($message->{'args'});
        }
    }
}

sub release{
    my ($self, $args) = @_;

    push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RELEASE_SUCCESS, args => $args});
}

sub _build_p2ps{
    my $p2ps = shift;
    
    return SOAP::Data->name( p2ps => \SOAP::Data->value( SOAP::Data->name( capacity => $p2ps->{'capacity'} ),
                                                         SOAP::Data->name( directionality => $p2ps->{'directionality'} ),
                                                         SOAP::Data->name( sourceSTP => $p2ps->{'sourceSTP'} ),
                                                         SOAP::Data->name( destSTP => $p2ps->{'destSTP'} )))->uri('http://schemas.ogf.org/nsi/2013/12/services/point2point');
    
}

sub _build_schedule{
    my $schedule = shift;
    if($schedule->{'startTime'} ne ''){
        return SOAP::Data->name( schedule => \SOAP::Data->value( SOAP::Data->name( startTime => $schedule->{'startTime'})->type('ftypes:DateTimeType'),
                                                                 SOAP::Data->name( endTime => $schedule->{'endTime'})->type('ftypes:DateTimeType')));
    }

    return SOAP::Data->name( schedule => \SOAP::Data->value( SOAP::Data->name( endTime => $schedule->{'endTime'} )->type('ftypes:DateTimeType')));
}

sub _build_criteria{
    my $criteria = shift;
    
    return SOAP::Data->name(criteria => 
                            \SOAP::Data->value( _build_schedule( $criteria->{'schedule'}),
                                                SOAP::Data->name( serviceType => $criteria->{'serviceType'}->{'type'}),
                                                _build_p2ps( $criteria->{'p2ps'} )
                            ))->attr({ version => $criteria->{'version'}->{'version'}++});
    

}

sub _reserve_confirmed {
    my ($self, $data, $connection_id) = @_;

    log_debug("Sending Reservation Confirmation");
    warn Data::Dumper::Dumper($data);
    my $soap = SOAP::Lite->new->proxy($data->{'header'}->{'replyTo'})->ns('http://schemas.ogf.org/sni/2013/12/framework/types','ftypes')->ns('http://schemas.ogf.org/nsi/2013/12/framework/headers','header')->ns('http://schemas.ogf.org/nsi/2013/12/connection/types','ctypes');

    my $header = SOAP::Header->name("header:nsiHeader" => \SOAP::Data->value(
                                        SOAP::Data->name(protocolVersion => $data->{'header'}->{'protocolVersion'}),
                                        SOAP::Data->name(correlationId => $data->{'header'}->{'correlationId'}),
                                        SOAP::Data->name(requesterNSA => $data->{'header'}->{'requesterNSA'}),
                                        SOAP::Data->name(providerNSA => $data->{'header'}->{'providerNSA'})
                                    ));

    my $soap_response = $soap->reserveConfirmed($header, SOAP::Data->name(connectionId => $connection_id),
                                                SOAP::Data->name(globalReservationId => $data->{'globalReservationId'}),
                                                SOAP::Data->name(description => $data->{'description'}),
                                                _build_criteria($data->{'criteria'}) 
        );
                                                
}

sub _reserve_commit_confirmed{
    my ($self, $data) = @_;


    my $soap = SOAP::Lite->new->proxy($data->{'header'}->{'replyTo'})->ns('http://schemas.ogf.org/sni/2013/12/framework/types','ftypes')->ns('http://schemas.ogf.org/nsi/2013/12/framework/headers','header')->ns('http://schemas.ogf.org/nsi/2013/12/connection/types','ctypes');    
    my $header = SOAP::Header->name("header:nsiHeader" => \SOAP::Data->value(
                                        SOAP::Data->name(protocolVersion => $data->{'header'}->{'protocolVersion'}),
                                        SOAP::Data->name(correlationId => $data->{'header'}->{'correlationId'}),
                                        SOAP::Data->name(requesterNSA => $data->{'header'}->{'requesterNSA'}),
                                        SOAP::Data->name(providerNSA => $data->{'header'}->{'providerNSA'})
                                    ));

    my $soap_response = $soap->reserveCommitConfirmed($header, SOAP::Data->name(connectionId => $data->{'connectionId'}));
    
}

sub _reserve_failed {
    my ($self, $data) = @_;

    log_debug("Sending Reservation Failure");
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

    $websvc->{'debug'} = 1;

    $self->{'websvc'} = $websvc;

    $self->{'websvc_user'}     = $self->{'config'}->get('/config/oess-service/@username');
    $self->{'websvc_pass'}     = $self->{'config'}->get('/config/oess-service/@password');
    $self->{'websvc_realm'}    = $self->{'config'}->get('/config/oess-service/@realm');
    $self->{'websvc_location'} = $self->{'config'}->get('/config/oess-service/@web-service');

    warn Data::Dumper::Dumper($self);

    $self->{'websvc'}->set_credentials(
        'uid' => $self->{'websvc_user'},
        'passwd' => $self->{'websvc_pass'},
	'realm' => $self->{'websvc_realm'}
        );

    $self->{'workgroup_id'} = $self->{'config'}->get('/config/oess-service/@workgroup-id');

    $self->{'reservation_queue'} = [];
}

sub _release_confirmed{
    my ($self, $data) = @_;

    my $soap = SOAP::Lite->new->proxy($data->{'header'}->{'replyTo'})->ns('http://schemas.ogf.org/sni/2013/12/framework/types','ftypes')->ns('http://schemas.ogf.org/nsi/2013/12/framework/headers','header')->ns('http://schemas.ogf.org/nsi/2013/12/connection/types','ctypes');
    my $header = SOAP::Header->name("header:nsiHeader" => \SOAP::Data->value(
                                        SOAP::Data->name(protocolVersion => $data->{'header'}->{'protocolVersion'}),
                                        SOAP::Data->name(correlationId => $data->{'header'}->{'correlationId'}),
                                        SOAP::Data->name(requesterNSA => $data->{'header'}->{'requesterNSA'}),
                                        SOAP::Data->name(providerNSA => $data->{'header'}->{'providerNSA'})
                                    ));

    my $soap_response = $soap->releaseConfirmed($header, SOAP::Data->name(connectionId => $data->{'connectionId'}));
}

1;
