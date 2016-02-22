#!/usr/bin/perl

package OESS::NSI::Utils;
use strict;
use OESS::Database;
use Data::UUID;
use GRNOC::Log;

=head2 build_client

=cut

sub build_client{
    my %params = @_;

    log_debug("building client");
    log_debug("Sending Request to " . $params{'proxy'});

    my $soap;
    if($params{'ssl'}->{'enable'} || $params{'ssl'}->{'enabled'}){
        log_debug("Using SSL: " . Data::Dumper::Dumper($params{'ssl'}));
        $ENV{HTTPS_CERT_FILE} = $params{'ssl'}->{'cert'};
        $ENV{HTTPS_KEY_FILE}  = $params{'ssl'}->{'key'};
        $soap = SOAP::Lite->new->proxy( $params{'proxy'}, ssl_opts => {SSL_cert_file => $params{'ssl'}->{'cert'},
                                                                       SSL_key_file => $params{'ssl'}->{'key'}});
    }else{
        log_debug("Not using SSL");
        $soap = SOAP::Lite->new->proxy( $params{'proxy'});
    }

    $soap->ns('http://schemas.ogf.org/sni/2013/12/framework/types','ftypes');
    $soap->ns('http://schemas.ogf.org/nsi/2013/12/framework/headers','header');
    $soap->uri('http://schemas.ogf.org/nsi/2013/12/connection/types','ctypes');

    $soap->serializer->encodingStyle('');

    return $soap;
}

=head2 build_header

=cut

sub build_header{
    my $header = shift;    

    log_debug("building NSI SOAP Header");

    if(!defined($header->{'protocolVersion'})){
        $header->{'protocolVersion'} = "application/vnd.ogf.nsi.cs.v2.requester+soap";
    }

    if(!defined($header->{'correlationId'})){
        my $ug = Data::UUID->new;
        $header->{'correlationId'} = "urn:uuid:" . $ug->to_string($ug->create());
    }

    if(!defined($header->{'requesterNSA'})){
        log_error("RequesterNSA is required in the NSI Header!\n");
        return;
    }

    if(!defined($header->{'providerNSA'})){
        my $db = OESS::Database->new();
        my $dn = $db->get_local_domain_name();
        my $providerNSA = "nsi" . $dn . ":2013:nsa";
        $header->{'providerNSA'} = $providerNSA;
    }

    log_debug("NSI HEADER: protocolVersion: " . $header->{'protocolVersion'} . ", correlationId: " . $header->{'correlationId'} . ", requesterNSA: " . $header->{'requesterNSA'} . ", providerNSA: " . $header->{'providerNSA'});

    my $header_info = SOAP::Data->value(
        SOAP::Data->name( protocolVersion => $header->{'protocolVersion'})->type(''),
        SOAP::Data->name( correlationId => $header->{'correlationId'})->type(''),
        SOAP::Data->name( requesterNSA => $header->{'requesterNSA'})->type(''),
        SOAP::Data->name( providerNSA => $header->{'providerNSA'})->type('') );
    
    if(defined($header->{'sessionSecurityAttr'}) && $header->{'sessionSecurityAttr'} ne ''){
        $header_info->value($header_info->value(), SOAP::Data->name(sessionSecurityAttr => $header->{'sessionSecurityAttr'})->type(''));
    }
    
    my $header = SOAP::Header->name( 'header:nsiHeader' => \$header_info)->attr({ 'xmlns:header' => 'http://schemas.ogf.org/nsi/2013/12/framework/headers'});
    
    return $header;
}


1;
