#!/usr/bin/perl
##----- OSCARS 0.6 Client module
##-----
##----- $HeadURL: svn+ssh://svn.grnoc.iu.edu/grnoc/oe-ss/perl-lib/OSCARS/trunk/lib/OSCARS/Client.pm $ 
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----
##----- Provides a SOAP api to talk to OSCARS 0.6 instances
##----------------------------------------------------------------------
##
##   Copyright 2011 Trustees of Indiana University
##
##   Licensed under the Apache License, Version 2.0 (the "License");
##   you may not use this file except in compliance with the License.
##   You may obtain a copy of the License at
##
##       http://www.apache.org/licenses/LICENSE-2.0
##
##   Unless required by applicable law or agreed to in writing, software
##   distributed under the License is distributed on an "AS IS" BASIS,
##   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
##   See the License for the specific language governing permissions and
##   limitations under the License.
#
      
package OSCARS::Client;

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Headers;
use Data::Dumper;
use XML::XPath;
use XML::LibXML;

#constants found in https://oscars.es.net/repos/oscars/branches/common-anycast/oscars-client/src/main/java/net/es/oscars/client/OSCARSClient.java
use constant {
    STATUS_ACCEPTED => "ACCEPTED",       # createReservation is authorized, gri is assigned
     STATUS_INPATHCALCULATION => "INPATHCALCULATION",   #start local path calculation
     STATUS_PATHCALCULATED  => "PATHCALCULATED", # whole path calculation done
     STATUS_INCOMMIT => "INCOMMIT",       # in commit phase for calculated path
     STATUS_COMMITTED => "COMMITTED",     # whole path resources committed
     STATUS_RESERVED => "RESERVED",       # all domains have committed resources
     STATUS_INSETUP => "INSETUP",         # circuit setup has been started
     STATUS_ACTIVE => "ACTIVE",           # entire circuit has been setup
     STATUS_INTEARDOWN => "INTEARDOWN",   # circuit teardown has been started
     STATUS_FINISHED => "FINISHED",       # reservation endtime reached with no errors, circuit has been torndown
     STATUS_CANCELLED => "CANCELLED",     # complete reservation has been canceled, no circuit
     STATUS_FAILED => "FAILED",           # reservation failed at some point, no circuit
     STATUS_INMODIFY => "INMODIFY",       # reservation is being modified
     STATUS_INCANCEL => "INCANCEL",       # reservation is being canceled
     STATUS_OK => "Ok",
     TOPIC_RESERVATION => "idc:RESERVATION",
};


=head1 NAME

OSCARS-Client -Perl module for Talking to the OSCARS API (0.6)

=cut

our $VERSION = '1.1.2';

=head1 SYNOPSIS

A module to talk to the OSCARS API (0.6)

example:

=cut

=head2 new

    creates a new instance of an OSCARS::Client

    params
       cert: (required) path to the SSL certificate
       key: (required) path to the SSL key
       url: (required) url to the OSCARS API
       debug: (optional) 0|1 default is 0
       timeout: (optional) timout value in ms default is 10000


=cut


sub new{
    my $that = shift;
    my $class = ref($that) || $that;

    my %args = @_;
    
    my $self = \%args;
    bless $self, $class;

    if(!defined($self->{'cert'})){
	warn "cert was not defined\n";
	return undef;
    }

    if(! -e $self->{'cert'}){
	warn "unable to find certificate " . $self->{'cert'};
	return undef;
    }

    if(!defined($self->{'key'})){
	warn "key was not defined\n";
	return undef;
    }

    if(! -e $self->{'key'}){
	warn "unable to find key " . $self->{'key'};
    }

    if(!defined($self->{'url'})){
	warn "url was not defined\n";
	return undef;
    }

    if(!defined($self->{'debug'})){
	$self->{'debug'} = 0;
    }

    if(!defined($self->{'timeout'})){
	$self->{'timeout'} = 10 * 1000;
    }

    
    $self->{'cert_content'} = "";

    open(FILE, '<', $self->{'cert'});
    while(<FILE>){
	if($_ =~ /-----BEGIN CERTIFICATE-----/ || $_ =~ /-----END CERTIFICATE-----/){
	    next;
	}
	$self->{'cert_content'} .= $_;
    }
    close(FILE);

    #setup the environment for HTTPS
    $ENV{HTTPS_DEBUG}     = $self->{'debug'};
    $ENV{HTTPS_VERSION}   = '3';
    $ENV{HTTPS_CERT_FILE} = $self->{'cert'};
    $ENV{HTTPS_KEY_FILE}  = $self->{'key'};

    $self->{'ua'} = LWP::UserAgent->new ('timeout' => $self->{'timeout'});

    $self->{'error'} = ();
    
    return $self;
}


=head2 create_reservation

    creates a new circuit reservation in the OSCARS system
    
    params:
       src_urn
       dst_urn
       src_vlan
       dst_vlan
       bandwidth
       start_time
       end_time
       description

=cut

sub create_reservation{
    my $self = shift;
    my %params = @_;
    
    my $src_urn = $params{'src_urn'};
    my $dst_urn = $params{'dst_urn'};
    my $src_vlan = $params{'src_vlan'};
    my $dst_vlan = $params{'dst_vlan'};
    my $bandwidth = $params{'bandwidth'};
    my $start_time = $params{'start_time'};
    my $end_time = $params{'end_time'};
    my $description = $params{'description'};

    if(!defined($src_urn) || $src_urn eq ''){
	return {error => 'src_urn was not defined'};
    }

    if(!defined($dst_urn) || $dst_urn eq ''){
	return {error => 'dst_urn was not defined'};
    }

    $src_urn = $self->_escape_urn($src_urn);
    $dst_urn = $self->_escape_urn($dst_urn);

    if(!defined($description)){
        return {error => 'description was not defined'};
    }

    if(!defined($start_time)){
        return {error => 'start_time was not defined'};
    }

    if(!defined($end_time)){
        return {error => 'end_time was not defined'};
    }

    if(!defined($bandwidth) || $bandwidth < 1){
        $bandwidth = 1;
    }
    my $src_tagged = "true";
    if($src_vlan == -1){
        $src_tagged = "false";
    }
    my $dst_tagged = "true";

    if($dst_vlan == -1){
        $dst_tagged = "false";
    }

    if ($start_time eq -1){
        $start_time = time();
    }

    if ($end_time eq -1){
        $end_time = time() + (2 * 635 * 24 * 60 * 60); # 2 years                                                                                                                                        
    }

    my $path_type = 'strict';

    my $body = '<ns3:createReservation xmlns="http://oscars.es.net/OSCARS/authParams" xmlns:ns10="http://docs.oasis-open.org/wsn/b-2" xmlns:ns11="http://docs.oasis-open.org/wsrf/r-2" xmlns:ns2="urn:oasis:names:tc:SAML:2.0:assertion" xmlns:ns3="http://oscars.es.net/OSCARS/06" xmlns:ns4="http://oscars.es.net/OSCARS/common" xmlns:ns5="http://ogf.org/schema/network/topology/ctrlPlane/20080828/" xmlns:ns6="http://www.w3.org/2000/09/xmldsig#" xmlns:ns7="http://www.w3.org/2001/04/xmlenc#" xmlns:ns8="http://docs.oasis-open.org/wsrf/bf-2" xmlns:ns9="http://www.w3.org/2005/08/addressing"><ns3:globalReservationId></ns3:globalReservationId><ns3:description>' . $description . '</ns3:description><ns3:userRequestConstraint><ns3:startTime>' . $start_time . '</ns3:startTime><ns3:endTime>' . $end_time . '</ns3:endTime><ns3:bandwidth>' . $bandwidth . '</ns3:bandwidth><ns3:pathInfo><ns3:pathSetupMode>timer-automatic</ns3:pathSetupMode><ns3:pathType>' . $path_type . '</ns3:pathType><ns3:layer2Info><ns3:srcVtag tagged="' . $src_tagged . '">' . $src_vlan . '</ns3:srcVtag><ns3:destVtag tagged="' . $dst_tagged . '">' . $dst_vlan . '</ns3:destVtag><ns3:srcEndpoint>'. $src_urn .'</ns3:srcEndpoint><ns3:destEndpoint>' . $dst_urn . '</ns3:destEndpoint></ns3:layer2Info></ns3:pathInfo></ns3:userRequestConstraint></ns3:createReservation>';

    my $signed_xml = $self->_create_signed_doc($body);
    warn "Signed docuemtn successfully\n";
    warn "URL: " . $self->{'url'} . "\n";
    my $messg = HTTP::Request->new('POST',$self->{'url'} , new HTTP::Headers, $signed_xml);
    $messg->header( 'SOAPAction' => "http://oscars.es.net/OSCARS/createReservation");
    $messg->content_type('text/xml');
    $messg->content_length( length($signed_xml));
    my $resp = $self->{'ua'}->request($messg);
    warn "Sent request\nResp: ". $resp;
    my ($xpath,$result) = $self->_process_response($resp);
    if(!defined($xpath) || !defined($result)){
	warn "Problem getting response\n";
	return undef;
    }


    my $gti = $xpath->find("./ns3:createReservationResponse/ns3:messageProperties/globalTransactionId",$result);
    $gti = $gti->string_value;

    my $gri = $xpath->find("./ns3:createReservationResponse/ns3:globalReservationId",$result);
    $gri = $gri->string_value;
    return ($gri,$gti)
}


=head2 cancel_reservation
    
    cancels a reservation

=cut

sub cancel_reservation{
    my $self = shift;
    my %params = @_;
    
    if(!defined($params{'gri'})){
	$self->_set_error("GRI Not defined");
	return undef;
    }

    
    my $body = '<ns3:cancelReservation xmlns="http://oscars.es.net/OSCARS/authParams" xmlns:ns10="http://docs.oasis-open.org/wsn/b-2" xmlns:ns11="http://docs.oasis-open.org/wsrf/r-2" xmlns:ns2="urn:oasis:names:tc:SAML:2.0:assertion" xmlns:ns3="http://oscars.es.net/OSCARS/06" xmlns:ns4="http://oscars.es.net/OSCARS/common" xmlns:ns5="http://ogf.org/schema/network/topology/ctrlPlane/20080828/" xmlns:ns6="http://www.w3.org/2000/09/xmldsig#" xmlns:ns7="http://www.w3.org/2001/04/xmlenc#" xmlns:ns8="http://docs.oasis-open.org/wsrf/bf-2" xmlns:ns9="http://www.w3.org/2005/08/addressing"><ns3:globalReservationId>' . $params{'gri'} . '</ns3:globalReservationId></ns3:cancelReservation>';
    
    my $signed_xml = $self->_create_signed_doc($body);

    my $messg = HTTP::Request->new('POST',$self->{'url'} , new HTTP::Headers, $signed_xml);
    $messg->header( 'SOAPAction' => "http://oscars.es.net/OSCARS/cancelReservation");
    $messg->content_type('text/xml');
    $messg->content_length( length($signed_xml));
    my $resp = $self->{'ua'}->request($messg);

    my ($xpath,$result) = $self->_process_response($resp);

    if (!defined $xpath || !defined $result){
	return undef;
    }

    my $gti = $xpath->find("./ns3:createReservationResponse/ns3:messageProperties/globalTransactionId",$result);
    $gti = $gti->string_value;

    my $gri = $xpath->find("./ns3:createReservationResponse/ns3:globalReservationId",$result);
    $gri = $gri->string_value;
    return ($gri,$gti)
}


=head2 list_reservations

=cut

sub list_reservations{

    my $self=shift;
    my %params = @_;
    my $reservations = [];
    my $soap_query;
    #assumptions: all parameters will be 
    my $parameter_map = {
        status => 'resStatus',
        start_time => 'startTime',
        end_time => 'endTime',
        vlan_tag => 'vlanTag',
        offset => 'resOffset',
        link_id => 'linkId',  
    };

    foreach my $key (keys %params){
        unless ($parameter_map->{$key}){
            next;
        }
        my $SOAP_parameter = $parameter_map->{$key};
        #many of the params can take multiples, vlanTags,resStatus
        if (ref($params{$key}) eq "ARRAY"){
            foreach my $value (@${$params{$key}}){
                $soap_query.='<ns3:'.$SOAP_parameter.'>'.$value.'</ns3:'.$SOAP_parameter.'>';
            }
           
        }
        else { 
            my $value = $params{$key};
            $soap_query.='<ns3:'.$SOAP_parameter.'>'.$value.'</ns3:'.$SOAP_parameter.'>';
        }
    }
    my $body = '<ns3:listReservations xmlns:ns10="http://docs.oasis-open.org/wsn/b-2" xmlns:ns11="http://docs.oasis-open.org/wsrf/r-2" xmlns:ns2="urn:oasis:names:tc:SAML:2.0:assertion" xmlns:ns3="http://oscars.es.net/OSCARS/06" xmlns:ns4="http://oscars.es.net/OSCARS/common" xmlns:ns5="http://ogf.org/schema/network/topology/ctrlPlane/20080828/" xmlns:ns6="http://www.w3.org/2000/09/xmldsig#" xmlns:ns7="http://www.w3.org/2001/04/xmlenc#" xmlns:ns8="http://docs.oasis-open.org/wsrf/bf-2" xmlns:ns9="http://www.w3.org/2005/08/addressing">'.
       $soap_query.  
      '</ns3:listReservations>';

    my $signed_xml = $self->_create_signed_doc($body);

    my $messg = HTTP::Request->new('POST',$self->{'url'} , new HTTP::Headers, $signed_xml);
    $messg->header( 'SOAPAction' => "http://oscars.es.net/OSCARS/listReservations");
    $messg->content_type('text/xml');
    $messg->content_length( length($signed_xml));
    my $resp = $self->{'ua'}->request($messg);

    my ($xpath,$result) = $self->_process_response($resp);
    #print $resp->content;
    #todo: filter result to reservations

    my $resDetails = $xpath->find('ns3:listReservationsResponse/ns3:resDetails', $result);
    #warn $resDetails->to_literal();
    foreach my $reservation (@$resDetails){
        my $tmp = {};
        
        if ($reservation){
            my $gri = $xpath->find('ns3:globalReservationId',$reservation);
            $tmp->{'gri'} = $gri->string_value;
            push (@$reservations, $tmp);
        }
    }

    #$reservations = $result;
    
    return $reservations;
}

=head2 query_reservation

=cut

sub query_reservation{
    my $self = shift;
    my %params = @_;
    
    if(!defined($params{'gri'})){
	$self->_set_error("query_reservation: gri was not defined");
	return undef;
    }
    
    my $body = '<ns3:queryReservation xmlns="http://oscars.es.net/OSCARS/authParams" xmlns:ns10="http://docs.oasis-open.org/wsn/b-2" xmlns:ns11="http://docs.oasis-open.org/wsrf/r-2" xmlns:ns2="urn:oasis:names:tc:SAML:2.0:assertion" xmlns:ns3="http://oscars.es.net/OSCARS/06" xmlns:ns4="http://oscars.es.net/OSCARS/common" xmlns:ns5="http://ogf.org/schema/network/topology/ctrlPlane/20080828/" xmlns:ns6="http://www.w3.org/2000/09/xmldsig#" xmlns:ns7="http://www.w3.org/2001/04/xmlenc#" xmlns:ns8="http://docs.oasis-open.org/wsrf/bf-2" xmlns:ns9="http://www.w3.org/2005/08/addressing"><ns3:globalReservationId>' . $params{'gri'} . '</ns3:globalReservationId></ns3:queryReservation>';

    my $signed_xml = $self->_create_signed_doc($body);

    my $messg = HTTP::Request->new('POST',$self->{'url'} , new HTTP::Headers, $signed_xml);
    $messg->header( 'SOAPAction' => "http://oscars.es.net/OSCARS/queryReservation");
    $messg->content_type('text/xml');
    $messg->content_length( length($signed_xml));
    my $resp = $self->{'ua'}->request($messg);
    my ($xpath,$result) = $self->_process_response($resp);
    
    if(!defined($xpath) || !defined($result)){
	return undef;
    }
    
    my $status = $xpath->find("./ns3:queryReservationResponse/ns3:reservationDetails/ns3:status",$result);
    $status = @$status[0]->string_value;
    
    my $message = $xpath->find("./ns3:queryReservationResponse/ns3:errorReport/ns4:errorMsg",$result);

    if (! $message || ! @$message[0]){
	$message = "";#return $status;
    }else{
	$message = @$message[0]->string_value;
    }

    my $hops = $xpath->find("./ns3:queryReservationResponse/ns3:reservationDetails/ns3:reservedConstraint/ns3:pathInfo/ns3:path/ns5:hop",$result);

    my @path;
    foreach my $hop (@$hops){
	my $urn = $xpath->findvalue("./ns5:link/\@id",$hop);
	push(@path,$urn->value());
    }

    return ($status,$message,\@path);

}

=head2 modify_reservation

=cut

sub modify_reservation{
    my $self = shift;
    my %params = @_;

    my $src_urn = $params{'src_urn'};
    my $dst_urn = $params{'dst_urn'};
    my $src_vlan = $params{'src_vlan'};
    my $dst_vlan = $params{'dst_vlan'};
    my $bandwidth = $params{'bandwidth'};
    my $start_time = $params{'start_time'};
    my $end_time = $params{'end_time'};
    my $description = $params{'description'};
    my $gri = $params{'gri'};

    if(!defined($src_urn) || $src_urn eq ''){
        return {error => 'src_urn was not defined'};
    }

    if(!defined($dst_urn) || $dst_urn eq ''){
        return {error => 'dst_urn was not defined'};
    }

    $src_urn = $self->_escape_urn($src_urn);
    $dst_urn = $self->_escape_urn($dst_urn);

    if(!defined($description)){
        return {error => 'description was not defined'};
    }

    if(!defined($start_time)){
        return {error => 'start_time was not defined'};
    }

    if(!defined($end_time)){
        return {error => 'end_time was not defined'};
    }

    if(!defined($bandwidth) || $bandwidth < 1){
        $bandwidth = 1;
    }
    my $src_tagged = "true";
    if($src_vlan == -1){
        $src_tagged = "false";
    }
    my $dst_tagged = "true";

    if($dst_vlan == -1){
        $dst_tagged = "false";
    }

    if ($start_time eq -1){
        $start_time = time();
    }

    if ($end_time eq -1){
        $end_time = time() + (2 * 635 * 24 * 60 * 60); # 2 years 
    }

    my $path_type = 'strict';

    my $body = '<ns3:modifyReservation xmlns="http://oscars.es.net/OSCARS/authParams" xmlns:ns10="http://docs.oasis-open.org/wsn/b-2" xmlns:ns11="http://docs.oasis-open.org/wsrf/r-2" xmlns:ns2="urn:oasis:names:tc:SAML:2.0:assertion" xmlns:ns3="http://oscars.es.net/OSCARS/06" xmlns:ns4="http://oscars.es.net/OSCARS/common" xmlns:ns5="http://ogf.org/schema/network/topology/ctrlPlane/20080828/" xmlns:ns6="http://www.w3.org/2000/09/xmldsig#" xmlns:ns7="http://www.w3.org/2001/04/xmlenc#" xmlns:ns8="http://docs.oasis-open.org/wsrf/bf-2" xmlns:ns9="http://www.w3.org/2005/08/addressing"><ns3:globalReservationId>' . $gri .'</ns3:globalReservationId><ns3:description>' . $description . '</ns3:description><ns3:userRequestConstraint><ns3:startTime>' . $start_time . '</ns3:startTime><ns3:endTime>' . $end_time . '</ns3:endTime><ns3:bandwidth>' . $bandwidth . '</ns3:bandwidth><ns3:pathInfo><ns3:pathSetupMode>timer-automatic</ns3:pathSetupMode><ns3:pathType>' . $path_type . '</ns3:pathType><ns3:layer2Info><ns3:srcVtag tagged="' . $src_tagged . '">' . $src_vlan . '</ns3:srcVtag><ns3:destVtag tagged="' . $dst_tagged . '">' . $dst_vlan . '</ns3:destVtag><ns3:srcEndpoint>'. 
$src_urn .'</ns3:srcEndpoint><ns3:destEndpoint>' . $dst_urn . '</ns3:destEndpoint></ns3:layer2Info></ns3:pathInfo></ns3:userRequestConstraint></ns3:modifyReservation>';

    my $signed_xml = $self->_create_signed_doc($body);

    my $messg = HTTP::Request->new('POST',$self->{'url'} , new HTTP::Headers, $signed_xml);
    $messg->header( 'SOAPAction' => "http://oscars.es.net/OSCARS/modifyReservation");
    $messg->content_type('text/xml');
    $messg->content_length( length($signed_xml));
    my $resp = $self->{'ua'}->request($messg);

    my $result = $self->_process_response($resp);
    
    return $result;
}

=head2 _create_signed_doc

    Creates a template and SOAP Envelope around an XML Blob and signs it.  The return value is a string containing the signed XML Blob.

=cut

sub _create_signed_doc{
    my $self = shift;
    my $xml = shift;

    my $time = time();
    my $timestamp_create = $self->_timestamp($time - (2 * 60));
    my $timestamp_expire = $self->_timestamp($time + (2 * 60));
    
    my $template = '<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">                                                                                                                     
  <soap:Header>                                                                                                                                                                                         
    <wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" soap:mustUnderstand="true">                                                           
      <wsse:BinarySecurityToken xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary" ValueType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-x509-token-profile-1.0#X509v3" wsu:Id="myCert">'. $self->{'cert_content'} . '</wsse:BinarySecurityToken>                                                                                                                 
      <wsu:Timestamp xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" wsu:Id="Timestamp">                                                                 
        <wsu:Created>' . $timestamp_create . '</wsu:Created>                                                                                                                                            
        <wsu:Expires>' . $timestamp_expire . '</wsu:Expires>                                                                                                                                            
      </wsu:Timestamp>                                                                                                                                                                                  
      <ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#" Id="Signature-2">                                                                                                                     
        <ds:SignedInfo>                                                                                                                                                                                 
          <ds:CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#" />                                                                                                             
          <ds:SignatureMethod Algorithm="http://www.w3.org/2000/09/xmldsig#rsa-sha1" />                                                                                                                 
          <ds:Reference URI="#myBody">                                                                                                                                                                  
            <ds:Transforms>                                                                                                                                                                             
              <ds:Transform Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#" />                                                                                                                      
            </ds:Transforms>                                                                                                                                                                            
            <ds:DigestMethod Algorithm="http://www.w3.org/2000/09/xmldsig#sha1" />                                                                                                                      
            <ds:DigestValue></ds:DigestValue>                                                                                                                                                           
          </ds:Reference>                                                                                                                                                                               
          <ds:Reference URI="#Timestamp">                                                                                                                                                               
            <ds:Transforms>                                                                                                                                                                             
              <ds:Transform Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#" />                                                                                                                      
            </ds:Transforms>                                                                                                                                                                            
            <ds:DigestMethod Algorithm="http://www.w3.org/2000/09/xmldsig#sha1" />                                                                                                                      
            <ds:DigestValue></ds:DigestValue>                                                                                                                                                           
          </ds:Reference>                                                                                                                                                                               
        </ds:SignedInfo>                                                                                                                                                                                
        <ds:SignatureValue />                                                                                                                                                                           
        <ds:KeyInfo>                                                                                                                                                                                    
          <wsse:SecurityTokenReference xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" wsu:Id="blah">                                                                                                                                                            
            <wsse:Reference xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" URI="#myCert" ValueType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-x509-token-profile-1.0#X509v3" />                                                                                                                                                                  
          </wsse:SecurityTokenReference>                                                                                                                                                                
        </ds:KeyInfo>                                                                                                                                                                                   
      </ds:Signature>                                                                                                                                                                                   
    </wsse:Security>                                                                                                                                                                                    
  </soap:Header><soap:Body xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" wsu:Id="myBody">' . $xml . '</soap:Body></soap:Envelope>';

    #we want a unique file for every time we do this
    #THIS NEEDS TO BE IMPROVED
    #NEED TO WRITE OUR OWN XMLSEC perlmodule
    my $file = "/tmp/unsigned_" . $time . ".xml";

    open(FILE, ">", $file);
    print FILE $template;
    close(FILE);
    
    #for taint purposes
    $ENV{'PATH'} = '';

    #sign it
    my $cmd = "/usr/bin/xmlsec1 --sign --privkey-pem " . $self->{'key'} . " --enabled-reference-uris empty,same-doc,local,remote --id-attr:Id Body --id-attr:Id Timestamp $file";
    my $signed_xml = `$cmd`;
    `/bin/rm $file`;
        
    return $signed_xml;
}

sub _process_response{
    my $self = shift;
    my $response = shift;

    if($response->is_success){
	warn "REsponse is successfull\n";
	#warn Dumper($response->content);
	my $xpath = XML::XPath->new(xml => $response->content);
	$xpath->set_namespace("soap", "http://www.w3.org/2003/05/soap-envelope");
	$xpath->set_namespace("ns3","http://oscars.es.net/OSCARS/06");
	$xpath->set_namespace("ns4","http://oscars.es.net/OSCARS/common");
	my $nodes = $xpath->find("/soap:Envelope/soap:Body");
	my $node = @$nodes[0];
	return ($xpath,$node);
    }else{
	my $xpath = XML::XPath->new(xml => $response->content);
	$xpath->set_namespace("soap", "http://www.w3.org/2003/05/soap-envelope");
	my $reason = $xpath->find("/soap:Envelope/soap:Body/soap:Fault/soap:Reason/soap:Text");
	$reason = @{$reason}[0];
	warn "Failed because: " . $reason->string_value . "\n";
	$self->_set_error($reason->string_value);
	return undef;
    }
}

=head2 _timestamp

    returns the WSS formatted timestamp based on the unix timestamp passed in

=cut

sub _timestamp{
    my $self = shift;
    my $time = shift;
    my ($sec,$min,$hour,$mday,$mon,$year,undef,undef,undef) = gmtime($time);
    $mon++;
    $year = $year + 1900;
    return sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ",$year,$mon,$mday,$hour,$min,$sec);
}

=head2 _escape_urn

  since the urns are dyanmic based on names the user sets.. it is possible the urn might contain ' ' or : so we need to escape those out

=cut

sub _escape_urn{
    my $self = shift;
    my $urn = shift;
    
    $urn =~ /(.*)node=(.*):port=(.*):link=(.*)/;
    my $new_urn = $1;
    my $node = $2;
    my $port = $3;
    my $link = $4;

    $node =~ s/ /\%20/g;
    $node =~ s/:/\%3A/g;
    $new_urn .= "node=" . $node;

    $port =~ s/ /\%20/g;
    $port =~ s/:/\%3A/g;
    $new_urn .= ":port=" . $port;

    $link=~ s/ /\%20/g;
    $link =~ s/:/\%3A/g;
    $new_urn .= ":link=" . $link;

    return $new_urn;
}


sub _set_error{
    my $self = shift;
    my $error = shift;
    push(@{$self->{'error'}},$error);
}

sub get_error{
    my $self = shift;
    return $self->{'error'};
}

sub clear_error{
    my $self = shift;
    $self->{'error'} = ();
}



1;
