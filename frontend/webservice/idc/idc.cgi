#!/usr/bin/perl 

use strict;
use warnings;
use CGI;
use Data::Dumper;
use OSCARS::pss;
use XML::Simple;
use Switch;
use Log::Log4perl;


Log::Log4perl::init('/etc/oess/logging.conf');

my $cgi = new CGI;

my $action = $ENV{'HTTP_SOAPACTION'};

if(!defined($action)){

    #ok using content type
    my $tmp = $ENV{'CONTENT_TYPE'};
    $tmp =~ /action="(.*)"/;
    $action = $1;
}

switch($action){
    case "http://oscars.es.net/OSCARS/pss/setup" {
	my $raw_xml = $cgi->param('POSTDATA');
	OSCARS::pss::setupReq($raw_xml);
    }
    case "http://oscars.es.net/OSCARS/pss/teardown" {
	my $raw_xml = $cgi->param('POSTDATA');
	OSCARS::pss::teardownReq($raw_xml);    
    }else{
	print STDERR "Unknown action: " . Dumper($action) . "\n";
    }
};

print $cgi->header( 'text/plain' );
print '<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope"><soap:Body>                                                                                                                                                                      
    <setupResponse xmlns="http://oscars.es.net/OSCARS/pss" xmlns:ns2="http://oscars.es.net/OSCARS/06" xmlns:ns3="http://ogf.org/schema/network/topology/ctrlPlane/20080828/" xmlns:ns4="http://www.w3.org/2000/09/xmldsig#" xmlns:ns5="http://www.w3.org/2001/04/xmlenc#" xmlns:ns6="urn:oasis:names:tc:SAML:2.0:assertion" xmlns:ns7="http://oscars.es.net/OSCARS/authParams" xmlns:ns8="http://oscars.es.net/OSCARS/common" transactionId="nddi.net.internet2.edu-RM-963cb177-24eb-4f24-98f0-95778bf01481"></setupResponse></soap:Body></soap:Envelope>';

