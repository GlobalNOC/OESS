#!/usr/bin/perl -T
#
##----- NDDI OESS Remote.cgi
##-----
##----- $HeadURL: svn+ssh://svn.grnoc.iu.edu/grnoc/oe-ss/frontend/trunk/webservice/remote.cgi $
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----
##----- Communicates with an IDC to implement a cross domain circuit
##
##-------------------------------------------------------------------------
##
##
## Copyright 2011 Trustees of Indiana University
##
##   Licensed under the Apache License, Version 2.0 (the "License");
##  you may not use this file except in compliance with the License.
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
use strict;
use warnings;

use CGI;
use JSON;
use Switch;
use Data::Dumper;
use URI::Escape;

use OESS::Database;
use OESS::Topology;

use OSCARS::Client;

use LWP::UserAgent;
use HTTP::Request;
use HTTP::Headers;

use XML::XPath;

my $db   = new OESS::Database();
my $topo = new OESS::Topology();
print STDERR "HOST: " . $db->get_oscars_host() . "\n";
warn "oscars cert: ".$db->get_oscars_cert();
my $oscars = OSCARS::Client->new( 
    cert => $db->get_oscars_cert(),
    key => $db->get_oscars_key(),
    url => $db->get_oscars_host() . ":9001/OSCARS",
    debug => 1,
    timeout => 60000
    );

my $PS_TS = $db->get_oscars_topo();

my $LOCAL_DOMAIN = $db->get_local_domain_name();

my $cgi  = new CGI;

$| = 1;

sub main {

    if (! $db){
    send_json({"error" => "Unable to connect to database."});
    exit(1);
    }

    my $action = $cgi->param('action');
    
    my $user = $db->get_user_by_id( user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];
    if ($user->{'status'} eq 'decom') {
        $action = "error";
    }
  
    my $output;

    switch ($action){

    case "get_networks" {
        $output = &get_networks();
    }
    case "create_reservation" {
        $output = &create_reservation();
    }
    case "query_reservation" {
        $output = &query_reservation();
    }
    case "cancel_reservation"{
        $output = &cancel_reservation();
    }
    case "modify_reservation" {
        $output = &modify_reservation();
    }case "update_circuit_owner" {
	$output = &update_circuit_owner();
    }
    case "error" {
        $output = {error => "Decommed users cannot use webservices."};
    }
    else{
        $output = {error => "Unknown action - $action"};
    }

    }

    send_json($output);

}

sub get_networks {
    my $results;

    my $workgroup_id = $cgi->param('workgroup_id');

    # Make a SOAP envelope, use the XML file as the body.
    my $message = "";
    $message .= "<SOAP-ENV:Envelope xmlns:SOAP-ENC=\"http://schemas.xmlsoap.org/soap/encoding/\"\n";
    $message .= "                   xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\"\n";
    $message .= "                   xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"\n";
    $message .= "                   xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\">\n";
    $message .= "  <SOAP-ENV:Header/>\n";
    $message .= "  <SOAP-ENV:Body>\n";
    #body goes here
    $message .= '<nmwg:message type="TSQueryRequest" id="msg1" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" xmlns:xquery="http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/">
  <nmwg:metadata id="meta1">
    <nmwg:eventType>http://ggf.org/ns/nmwg/topology/20070809</nmwg:eventType>
  </nmwg:metadata>
  <nmwg:data metadataIdRef="meta1" id="d1" />
</nmwg:message>';
    #end body
    $message .= "  </SOAP-ENV:Body>\n";
    $message .= "</SOAP-ENV:Envelope>\n";


    my $ua = LWP::UserAgent->new ('timeout' => ( ((30*8) * 1000)));
    my $messg = HTTP::Request->new('POST',$PS_TS , new HTTP::Headers, $message);
    $messg->header( 'SOAPAction' => "http://ggf.org/ns/nmwg/base/2.0/message/");
    $messg->content_type('text/xml');
    $messg->content_length( length($message));
    my $resp = $ua->request($messg);
    my $respContent;
    warn Data::Dumper->Dump([\$resp], ['resp']);
    if($resp->is_success){
    $respContent = $resp->content();

    $XML::XPath::Namespaces = 0;

    my $xpath = XML::XPath->new(xml => $respContent);
    $xpath->set_namespace("SOAP-ENC", "http://schemas.xmlsoap.org/soap/encoding/");
    $xpath->set_namespace("SOAP-ENV", "http://schemas.xmlsoap.org/soap/envelope/");
    $xpath->set_namespace("xsd", "http://www.w3.org/2001/XMLSchema");
    $xpath->set_namespace("xsi", "http://www.w3.org/2001/XMLSchema-instance");
    $xpath->set_namespace("nmwg", "http://ggf.org/ns/nmwg/base/2.0/");
    $xpath->set_namespace("ns1", "http://ogf.org/schema/network/topology/ctrlPlane/20080828/");
    $xpath->set_namespace("nmtopo", "http://ogf.org/schema/network/topology/base/20070828/");

    my %LOOKUP;

    # get a listing of all the lat/long info we know about first to avoid doing lots of queries
    my $node_lat_longs = $db->_execute_query("select name, latitude, longitude from node");
    foreach my $row (@$node_lat_longs){
        $LOOKUP{'nodes'}{$row->{'name'}} = {"longitude" => $row->{'longitude'},
                        "latitude"  => $row->{'latitude'}
                                            };
    }

    # get a listing of all the lat/long info we know about first to avoid doing lots of queries
    my $net_lat_longs = $db->_execute_query("select name, latitude, longitude, is_local from network");
    foreach my $row (@$node_lat_longs){
        $LOOKUP{'networks'}{$row->{'name'}} = {"longitude" => $row->{'longitude'},
                           "latitude"  => $row->{'latitude'},
                           "is_local"  => $row->{'is_local'}
                                               };
    }

    my $DOMAIN_BASE = "/SOAP-ENV:Envelope/SOAP-ENV:Body/nmwg:message/nmwg:data/nmtopo:topology/ns1:domain";

    my $domain_elements = $xpath->find($DOMAIN_BASE);

    my @domains;

    foreach my $domain_element (@$domain_elements){

        my $domain = $domain_element->getAttribute("id");
        $domain =~ /urn:ogf:network:domain=(.*)/;
        my $domain_name = $1;
        my @links;
        my $node_elements = $xpath->find("./ns1:node", $domain_element);

        foreach my $node_element (@$node_elements){
        
        my $node  = $node_element->getAttribute("id");
        my $port_elements = $xpath->find("./ns1:port", $node_element);
        
        foreach my $port_element (@$port_elements){
        
        my $port = $port_element->getAttribute('id');
        my $link_elements = $xpath->find("./ns1:link", $port_element);
        
        foreach my $link_element (@$link_elements){
            
            my $link = $link_element->getAttribute('id');
            
            my $remote_link = $xpath->find("./ns1:remoteLinkId", $link_element);
            
            my $remote_link_urn = @$remote_link[0]->getChildNodes()->[0]->getValue();
            
            my @tmp = split(':', $link);
            my $node_name = $tmp[4];
            my $port_name = $tmp[5];
            my $link_name = $tmp[6];
            $node_name =~ s/node=//g;
            $port_name =~ s/port=//g;
            $link_name =~ s/link=//g;
            
            if ($domain_name ne $LOCAL_DOMAIN){
               $node_name = $domain_name . "-" . $node_name;
            }
            
            my $latlong = $LOOKUP{'nodes'}{$node_name};
            
            if (! $latlong || ($latlong->{'latitude'} eq 0 && $latlong->{'longitude'} eq 0)){
                $latlong = $LOOKUP{'networks'}{$domain_name};
            }
            
            # if it's in the local domain and we have a workgroup specified, make sure it's
            # part of the workgroup auth
            if (defined $workgroup_id){
            
                my $is_local = $LOOKUP{'networks'}{$domain_name}{'is_local'};
                if ($is_local eq 1){
                    my $auth = $db->_execute_query(
                        "select 1 from workgroup_interface_membership " .
                        " join interface on interface.interface_id = workgroup_interface_membership.interface_id " .
                        " join node on node.node_id = interface.node_id " .
                        " where workgroup_id = ? and interface.name = ? and node.name = ?",
                        [$workgroup_id, $port_name, $node_name]
                    );
                    # didn't find a membership, skip this
                    next if ($auth && @$auth < 1);
                }
            
            }
            my $vlan_range;
            my $vlanRange = $xpath->find(
                "./ns1:SwitchingCapabilityDescriptors/ns1:switchingCapabilitySpecificInfo/ns1:vlanRangeAvailability", 
                $link_element
            );
            if(defined(@$vlanRange[0])){
                $vlanRange = @$vlanRange[0]->getChildNodes();
                if(defined($vlanRange->[0])){
                    $vlan_range = $vlanRange->[0]->getValue();
                }
            }

            push(@links,{
                urn        => $link,
                node       => $node_name,
                vlan_range => $vlan_range,
                port       => $port_name ,
                link       => $link_name,
                remote_urn => $remote_link_urn,
                latitude   => $latlong->{'latitude'},
                longitude  => $latlong->{'longitude'}
             });
            
        }}}#end forloop hell

        @links = sort {
            if ($a->{'node'} eq $b->{'node'}){
                return $a->{'port'} cmp $b->{'port'};
            }
            return $a->{'node'} cmp $b->{'node'};
        } @links;
        push(@domains,{ name => $domain_name, urn => $domain, links => \@links});
    }
    
    @domains = sort { $a->{'name'} cmp $b->{'name'} } @domains;
   
    warn"opening file"; 
    my $text = {'results' => \@domains};
    open(FILE, '>/tmp/results.txt');
    print FILE Dumper($text);
    close(FILE);
    warn"closing file"; 
    return {'results' => \@domains};
    }
    else{
        return {'error' => 'Error retreiving remote topologies'};
    }

}

sub create_reservation{

    my $src_urn = $cgi->param('src_urn');
    my $dst_urn = $cgi->param('dst_urn');
    my $src_vlan = $cgi->param('src_vlan');
    my $dst_vlan = $cgi->param('dst_vlan');
    my $bandwidth = $cgi->param('bandwidth');
    my $start_time = $cgi->param('start_time');
    my $end_time = $cgi->param('end_time');
    my $description = $cgi->param('description');


    # swap the src and dst around to try and make sure that we send a local one first.
    # OSCARS will not work unless the local network comes first for some reason.
    if ($src_urn !~ /domain=$LOCAL_DOMAIN/){
    my $tmp  = $src_urn;
    $src_urn = $dst_urn;
    $dst_urn = $tmp;

    $tmp      = $src_vlan;
    $src_vlan = $dst_vlan;
    $dst_vlan = $tmp;
    }

    my ($gri,$gti) = $oscars->create_reservation(
    src_urn => $src_urn,
    dst_urn => $dst_urn,
    src_vlan => $src_vlan,
    dst_vlan => $dst_vlan,
    bandwidth => $bandwidth,
    start_time => $start_time,
    end_time => $end_time,
    description => $description
    );

    if(!defined($gri) || !defined($gti)){
    return {error => $oscars->get_error()};
    }
    return {results => [{gri => $gri, gti => $gti}]};;

}

sub query_reservation{

    my $circuit_id = $cgi->param("circuit_id");
    my $gri        = $cgi->param("gri");

    if (! $gri){
    $gri = $db->get_circuit_by_id(circuit_id => $circuit_id)->[0]->{'external_identifier'};
    }

    if (! $gri){
    return {error => "Unable to get GRI for circuit $circuit_id to cancel reservation."};
    }

    my ($status,$message,$path) = $oscars->query_reservation( gri => $gri);

    if(!defined($status)){
    return {error => $oscars->get_error()};
    }

    my @path_struct;

    my ($prev_data, $curr_data);

    foreach my $link_urn (@$path){

    $link_urn =~ /domain=(\S+):node=(\S+):port=(\S+):link=(\S+)/;

    my $domain = $1;
    my $node   = $2;
    my $port   = $3;
    my $link   = $4;

    if ($domain ne $LOCAL_DOMAIN){
        $node = $domain . "-" . $node;
    }

    my $latlong = $db->_execute_query("select latitude, longitude from node where name = ?",
                      [$node]
        )->[0];

    if (! $latlong || ($latlong->{'latitude'} eq 0 && $latlong->{'longitude'} eq 0)){
        $latlong = $db->_execute_query("select latitude, longitude from network where name = ?", [$domain])->[0];
    }

    # couldn't find anything for this, default to 0,0
    if (! $latlong){
        $latlong = {"latitude" => 0, "longitude" => 0};
    }

    $curr_data = {"node" => $node,
                  "lon"  => $latlong->{"longitude"},
                  "lat"  => $latlong->{"latitude"}
                 };

    if ($prev_data){
        push(@path_struct, {"from_node" => $prev_data->{'node'},
                            "from_lon"  => $prev_data->{'lon'},
                            "from_lat"  => $prev_data->{'lat'},
                            "to_node"   => $curr_data->{'node'},
                            "to_lon"    => $curr_data->{'lon'},
                            "to_lat"    => $curr_data->{'lat'}
                           }
            );
    }

    $prev_data = $curr_data;
    }

    return {results => [{status => $status, message => $message, path => \@path_struct}]};

}

sub cancel_reservation{
    my $circuit_id = $cgi->param('circuit_id');

    my $gri = $db->get_circuit_by_id(circuit_id => $circuit_id)->[0]->{'external_identifier'};

    if (! $gri){
    return {error => "Unable to get GRI for circuit $circuit_id to cancel reservation."};
    }

    my ($status,$message) = $oscars->cancel_reservation( gri => $gri);

    if(!defined($status)){
    return {error => $oscars->get_error()};
    }

    return {results => [{status => $status, message => $message, gri => $gri}]};

}

sub update_circuit_owner{
    my $gri = $cgi->param('gri');
    my $workgroup_id = $cgi->param('workgroup_id');

    return {error => "No GRI Specified"} if(!defined($gri));
    return {error => "No Workgroup ID Specified"} if(!defined($workgroup_id));
			     
    my $circuit = $db->get_circuit_by_external_identifier( external_identifier => $gri );
    if(!defined($circuit)){
	return {error => "Unable to find circuit with GRI: " . $gri,
		results => []};
    }

    my $res = $db->update_circuit_owner( circuit_id => $circuit->{'circuit_id'}, workgroup_id => $workgroup_id );
    if(!defined($res)){
	return {error => "Error updating circuit ownership", results => [0]};
    }else{
	return {results => [{success => 1, message => "successfully update the circuit ownership"}]};
    }
    

}


sub modify_reservation{

    my $circuit_id = $cgi->param('circuit_id');
    my $src_urn = $cgi->param('src_urn');
    my $dst_urn = $cgi->param('dst_urn');
    my $src_vlan = $cgi->param('src_vlan');
    my $dst_vlan = $cgi->param('dst_vlan');
    my $bandwidth = $cgi->param('bandwidth');
    my $start_time = $cgi->param('start_time');
    my $end_time = $cgi->param('end_time');
    my $description = $cgi->param('description');
    my ($gri, $gti);

    $gri = $db->get_circuit_by_id(circuit_id => $circuit_id)->[0]->{'external_identifier'};

    if (! $gri){
    return {error => "Unable to get GRI for circuit $circuit_id to modify reservation."};
    }

    ($gri,$gti) = $oscars->modify_reservation( gri => $gri,
                           src_urn => $src_urn,
                           dst_urn => $dst_urn,
                           src_vlan => $src_vlan,
                           dst_vlan => $dst_vlan,
                           bandwidth => $bandwidth,
                           start_time => $start_time,
                           end_time => $end_time,
                           description => $description);

    if(!defined($gri) || !defined($gti)){
    return {error => $oscars->get_error()};
    }

    return {results => [{gri => $gri, gti => $gti}]};
}


sub send_json{
    my $output = shift;

    print "Content-type: text/plain\n\n" . encode_json($output);
}

main();

