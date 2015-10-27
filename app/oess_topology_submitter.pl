#!/usr/bin/perl

use strict;
use OESS::Database;
use LWP::UserAgent;


sub main{
    my $wg_name = shift;
    my $prefix = shift;
    

    my $db = OESS::Database->new();
    my $topology_xml = $db->gen_topo( $wg_name, $prefix);
    warn "TOPOLOGY: " . $topology_xml . "\n";
    my $httpEndpoint = $db->get_oscars_topo();

    my $results;
    
    my $xml = "";
    $xml .=
'<SOAP-ENV:Envelope xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/"
                   xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                   xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
             <SOAP-ENV:Header/>
             <SOAP-ENV:Body>';
    $xml .=
'<nmwg:message type="TSReplaceRequest" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/">
               <nmwg:metadata id="meta0">
                  <nmwg:eventType>http://ggf.org/ns/nmwg/topology/20070809</nmwg:eventType>
                     </nmwg:metadata>
                       <nmwg:data id="data0" metadataIdRef="meta0">';
    $xml .= $topology_xml;
    $xml .= '          </nmwg:data>
              </nmwg:message>
              </SOAP-ENV:Body>
              </SOAP-ENV:Envelope>';

    my $method_uri = "http://ggf.org/ns/nmwg/base/2.0/message/";
    my $userAgent = LWP::UserAgent->new( 'timeout' => 10 );
    my $sendSoap =
        HTTP::Request->new( 'POST', $httpEndpoint, new HTTP::Headers, $xml );
    $sendSoap->header( 'SOAPAction' => $method_uri );
    $sendSoap->content_type('text/xml');
    $sendSoap->content_length( length($xml) );

    my $httpResponse = $userAgent->request($sendSoap);

    if($httpResponse->code() == 200 && $httpResponse->message() eq 'success'){
        $results->{'results'} = [ { success => 1 } ];
    }else{
        $results->{'error'} = $httpResponse->message();
    }

}

main();
main("NSI","nsi");

