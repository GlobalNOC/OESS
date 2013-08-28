package OSCARS::pss;

use strict;
use warnings;
use Data::Dumper;
use XML::Writer;
use XML::XPath;
use SOAP::Data::Builder;
use URI::Escape;

use OESS::Database;
use OESS::DBus;

$ENV{HTTPS_DEBUG}     = 0;
$ENV{HTTPS_VERSION}   = '3';

my $OSCARS_USER        = "OSCARS";
my $IDC_WORKGROUP_NAME = "OSCARS IDC";

my $db   = new OESS::Database();
my $dbus = OESS::DBus->new( service => "org.nddi.fwdctl", instance => "/controller1");

my $LOCAL_DOMAIN = $db->get_local_domain_name();

$ENV{HTTPS_CERT_FILE} = $db->get_oscars_cert();
$ENV{HTTPS_KEY_FILE}  = $db->get_oscars_key();

if (! defined $dbus){
    die "Couldn't connect to dbus";
}


my $workgroup = $db->get_workgroup_details_by_name(name => $IDC_WORKGROUP_NAME);

if (! defined $workgroup){
    die "Unable to find workgroup $IDC_WORKGROUP_NAME, aborting.";
    return undef;
}

my $WORKGROUP_ID = $workgroup->{'workgroup_id'};



sub setupReq{

    my $input        = shift;

    my $parsed       = _parse_struct($input, "setupReq");

    my $username    = $OSCARS_USER; 

    my $description  = $parsed->{'description'};
    my $bandwidth    = $parsed->{'bandwidth'};
    my $links        = $parsed->{'links'};
    my $nodes        = $parsed->{'nodes'};
    my $interfaces   = $parsed->{'interfaces'};
    my $tags         = $parsed->{'tags'};
    my $remote_nodes = $parsed->{'remote_nodes'};
    my $remote_tags  = $parsed->{'remote_tags'};
    my $gri          = $parsed->{'gri'};

    my $result = $db->provision_circuit(description       => $description,
					bandwidth         => $bandwidth,
					provision_time    => -1,
					remove_time       => -1,
					links             => $links,
					backup_links      => [],
					nodes             => $nodes,
					interfaces        => $interfaces,
					tags              => $tags,
					user_name         => $username,
					workgroup_id      => $WORKGROUP_ID,
					external_id       => $gri,
					remote_endpoints  => $remote_nodes,
					remote_tags       => $remote_tags
	                               );


    my $xml;
    my $xml2;
    my $writer = new XML::Writer(OUTPUT => \$xml, DATA_INDENT => 2, DATA_MODE => 1, NAMESPACES => 1);
    my $writer2 = new XML::Writer(OUTPUT => \$xml2, DATA_INDENT => 2, DATA_MODE => 1, NAMESPACES => 1);
    
    $writer->startTag(["http://oscars.es.net/OSCARS/coord", "globalReservationId"]);
    $writer->characters($gri);
    $writer->endTag(["http://oscars.es.net/OSCARS/coord", "globalReservationId"]);

    # some failure
    if (! defined $result){

	my $error = $db->get_error();

	warn "Error! $error";

	$writer2->startTag(["http://oscars.es.net/OSCARS/coord", "status"]);
	$writer2->characters("FAILED");
	$writer2->endTag(["http://oscars.es.net/OSCARS/coord", "status"]);

    }
    # success!
    else{

	warn "Success!";

	my $circuit_id = $result->{'circuit_id'};
	
	my $output = $dbus->fire_signal("addVlan",$circuit_id);
	
	warn "fwdctl says: $output";

	$writer2->startTag(["http://oscars.es.net/OSCARS/coord", "status"]);
	$writer2->characters("SUCCESS");
	$writer2->endTag(["http://oscars.es.net/OSCARS/coord", "status"]);

    }
    
    $writer->end();
    $writer2->end();

    eval {

	my $callback_url = $db->get_oscars_host() . ":9003/OSCARS/Coord";

	my $method = SOAP::Data
	               -> name("PSSReplyReq")
		       -> attr({"replyType" => "setup"});

	SOAP::Lite
	    -> proxy($callback_url)
	    -> uri("http://oscars.es.net/OSCARS/coord")
	    -> call($method, 
		    SOAP::Data->type('xml' => $xml),
		    SOAP::Data->type('xml' => $xml2)
	    );
    };

    
    if ($@){
     	warn "Error was: " . $@;
    }
    else {
	warn "Sent successfully.";
    }

}

sub modifyReq {
    my $struct = shift;

    my $parsed = _parse_struct($struct, "modifyReq");

    my $description  = $parsed->{'description'};
    my $bandwidth    = $parsed->{'bandwidth'};
    my $links        = $parsed->{'links'};
    my $nodes        = $parsed->{'nodes'};
    my $interfaces   = $parsed->{'interfaces'};
    my $tags         = $parsed->{'tags'};
    my $remote_nodes = $parsed->{'remote_nodes'};
    my $remote_tags  = $parsed->{'remote_tags'};
    my $gri          = $parsed->{'gri'};

    my $username = $OSCARS_USER;

    my $circuit_info = $db->get_circuit_by_external_identifier(external_identifier => $gri);

    my $xml;
    my $xml2;

    my $writer = new XML::Writer(OUTPUT => \$xml, DATA_INDENT => 2, DATA_MODE => 1, NAMESPACES => 1);
    my $writer2 = new XML::Writer(OUTPUT => \$xml2, DATA_INDENT => 2, DATA_MODE => 1, NAMESPACES => 1);
    
    $writer->startTag(["http://oscars.es.net/OSCARS/coord", "globalReservationId"]);
    $writer->characters($gri);
    $writer->endTag(["http://oscars.es.net/OSCARS/coord", "globalReservationId"]);
    
    warn "Circuit info: " . Data::Dumper::Dumper($circuit_info);

    if (! $circuit_info){

	warn "Could not find circuit info for GRI = $gri";

	$writer2->startTag(["http://oscars.es.net/OSCARS/coord", "status"]);
	$writer2->characters("FAILED");
	$writer2->endTag(["http://oscars.es.net/OSCARS/coord", "status"]);

    }

    else {

	my $circuit_id = $circuit_info->{'circuit_id'};

	my $output = $dbus->fire_signal("deleteVlan", $circuit_info->{'circuit_id'});

	warn "fwdctl says: $output";

	my $result = $db->edit_circuit(circuit_id        => $circuit_id,
	                               description       => $description,
				       bandwidth         => $bandwidth,
				       provision_time    => -1,
				       remove_time       => -1,
				       links             => $links,
				       backup_links      => [],
				       nodes             => $nodes,
				       interfaces        => $interfaces,
				       tags              => $tags,
				       user_name         => $username,
				       workgroup_id      => $WORKGROUP_ID,
				       external_id       => $gri,
				       remote_endpoints  => $remote_nodes,
				       remote_tags       => $remote_tags,
				       do_external       => 1
	                               );
	
	warn "result is  " . Data::Dumper::Dumper($result);


	if (! defined $result){
	    $writer2->startTag(["http://oscars.es.net/OSCARS/coord", "status"]);
	    $writer2->characters("FAILED");
	    $writer2->endTag(["http://oscars.es.net/OSCARS/coord", "status"]);	    
	}
	else {	   

	    my $output = $dbus->fire_signal("addVlan",$circuit_id);

	    warn "fwdctl says: $output";

	    $writer2->startTag(["http://oscars.es.net/OSCARS/coord", "status"]);
	    $writer2->characters("SUCCESS");
	    $writer2->endTag(["http://oscars.es.net/OSCARS/coord", "status"]); 	    

	}
       
    }

    $writer->end();
    $writer2->end();

    eval {

	my $callback_url = $parsed->{'callback_url'}; 
	
	my $method = SOAP::Data
	    -> name("PSSReplyReq")
	    -> attr({"replyType" => "modify"});
	
	SOAP::Lite
	    -> proxy($callback_url)
	    -> uri("http://oscars.es.net/OSCARS/coord")
	    -> call($method, 
		    SOAP::Data->type('xml' => $xml),
		    SOAP::Data->type('xml' => $xml2)
	    );
    };
    
    
    if ($@){
     	warn "Error was: " . $@;
    }
    else {
	warn "Sent successfully.";
    }



}

sub teardownReq {
    my $struct       = shift;

    my $gri          = _get_gri($struct, "teardownReq");

    my $username     = $OSCARS_USER;

    eval{

    my $circuit_info = $db->get_circuit_by_external_identifier(external_identifier => $gri);

    my $xml;
    my $xml2;

    my $writer = new XML::Writer(OUTPUT => \$xml, DATA_INDENT => 2, DATA_MODE => 1, NAMESPACES => 1);
    my $writer2 = new XML::Writer(OUTPUT => \$xml2, DATA_INDENT => 2, DATA_MODE => 1, NAMESPACES => 1);
    
    $writer->startTag(["http://oscars.es.net/OSCARS/coord", "globalReservationId"]);
    $writer->characters($gri);
    $writer->endTag(["http://oscars.es.net/OSCARS/coord", "globalReservationId"]);
    
    warn "Circuit info: " . Data::Dumper::Dumper($circuit_info);

    if (! $circuit_info){

	$writer2->startTag(["http://oscars.es.net/OSCARS/coord", "status"]);
	$writer2->characters("FAILED");
	$writer2->endTag(["http://oscars.es.net/OSCARS/coord", "status"]);

    }
    else{

	my $output = $dbus->fire_signal("deleteVlan", $circuit_info->{'circuit_id'});

	warn "fwdctl says: $output";

	my $result = $db->remove_circuit(circuit_id  => $circuit_info->{'circuit_id'},
					 remove_time => -1,
					 username   => $username
	                                );

	if (! defined $result){
	    $writer2->startTag(["http://oscars.es.net/OSCARS/coord", "status"]);
	    $writer2->characters("FAILED");
	    $writer2->endTag(["http://oscars.es.net/OSCARS/coord", "status"]);	    
	}
	else {	   
	    $writer2->startTag(["http://oscars.es.net/OSCARS/coord", "status"]);
	    $writer2->characters("SUCCESS");
	    $writer2->endTag(["http://oscars.es.net/OSCARS/coord", "status"]); 	    
	}

    }

    eval {

	my $callback_url = $db->get_oscars_host() . ":9003/OSCARS/Coord";
	
	my $method = SOAP::Data
	    -> name("PSSReplyReq")
	    -> attr({"replyType" => "teardown"});
	
	SOAP::Lite
	    -> proxy($callback_url)
	    -> uri("http://oscars.es.net/OSCARS/coord")
	    -> call($method, 
		    SOAP::Data->type('xml' => $xml),
		    SOAP::Data->type('xml' => $xml2)
	    );
    };

    
    if ($@){
     	warn "Error was: " . $@;
    }
    else {
	warn "Sent successfully.";
    }

    };
    
    if ($@){
	warn "Error was overall: " . $@;
    }
    
}

sub statusReq {
    my $urn          = shift;
    my $callback_url = shift;
    my $request      = shift;

    eval {
	_send_response($callback_url);
		       
    };

    warn "Got a status: " . Data::Dumper::Dumper($request);
}

sub _get_gri {
    my $input = shift;
    my $type  = shift;

    $XML::XPath::Namespaces = 0;
    my $xpath = XML::XPath->new(xml => $input);

    my $setupReq = $xpath->find("/soap:Envelope/soap:Body/$type")->[0]; 
    my $request  = $xpath->find("./reservation", $setupReq)->[0]; 
    my $gri      = $xpath->find("./ns2:globalReservationId", $request)->[0]->getChildNodes()->[0]->getValue(); 

    return $gri;
}

sub _get_callback_url {
    my $input = shift;
    my $type  = shift;

    $XML::XPath::Namespaces = 0;
    my $xpath = XML::XPath->new(xml => $input);

    my $setupReq = $xpath->find("/soap:Envelope/soap:Body/$type")->[0]; 

    my $callback_url = $xpath->find("./callbackEndpoint", $setupReq)->[0]->getChildNodes()->[0]->getValue(); 

    return $callback_url;
}

sub _parse_struct {
    my $input = shift;
    my $type  = shift;

    $XML::XPath::Namespaces = 0;
    my $xpath = XML::XPath->new(xml => $input);

    my $setupReq = $xpath->find("/soap:Envelope/soap:Body/$type")->[0]; 

    my $callback_url = $xpath->find("./callbackEndpoint", $setupReq)->[0]->getChildNodes()->[0]->getValue(); 

    my $request     = $xpath->find("./reservation", $setupReq)->[0]; 

    my $description = $xpath->find("./ns2:description", $request)->[0]->getChildNodes()->[0]->getValue(); 
    my $gri         = $xpath->find("./ns2:globalReservationId", $request)->[0]->getChildNodes()->[0]->getValue(); 

    # in Mbps
    my $bandwidth = $xpath->find("./ns2:reservedConstraint/ns2:bandwidth", $request)->[0]->getChildNodes()->[0]->getValue();

    my %links;

    my @endpoints;
    
    # first real step is to figure out all the hops on this circuit that are relevant to us. We need to find all
    # the links and nodes that this circuit traverses on the local domain.

    my $hop_info = $xpath->find("./ns2:reservedConstraint/ns2:pathInfo/ns2:path/ns3:hop", $request);

    foreach my $hop (@$hop_info){

	my $link_element = $xpath->find("./ns3:link", $hop)->[0];

	my $link_urn = $link_element->getAttribute("id");

	warn "link: $link_urn";

	next unless ($link_urn =~ /domain=$LOCAL_DOMAIN/);

	$link_urn =~ /node=(\S+):port=(\S+):link=(\S+)/;

	my $node = $1;
	my $port = $2;
	my $link = $3;

	my $tag = $xpath->find("./ns3:SwitchingCapabilityDescriptors/ns3:switchingCapabilitySpecificInfo/ns3:suggestedVLANRange", $link_element)->[0];

	# if we have the tag defined, that means we're on an endpoint
	if ($tag){
	    $tag = $tag->getChildNodes()->[0]->getValue();	    
	    push(@endpoints, {"node" => $node, "port" => $port, "tag" => $tag});
	}
	# otherwise we're just passing through this element, note the link
	else{ 
	    $links{$link} = 1;
	}

    }

    # we must have 2 endpoints here, otherwise presume some parsing error
    if (@endpoints != 2){
	die "Didn't get two endpoints. I got: " . Data::Dumper::Dumper(\@endpoints);
    }


    # now let's figure out where the circuit actually terminates so we can keep a reference to the remote endpoint(s).
    # this might be inside of the local domain, it might be half in the local domain, or it might be entirely external.
    my $layer2_info = $xpath->find("./ns2:reservedConstraint/ns2:pathInfo/ns2:layer2Info", $request)->[0];

    my $remoteNodeA = $xpath->find("./ns2:srcEndpoint", $layer2_info)->[0]->getChildNodes()->[0]->getValue();
    my $remoteNodeZ = $xpath->find("./ns2:destEndpoint", $layer2_info)->[0]->getChildNodes()->[0]->getValue();

#    my $remoteTagA = $xpath->find("./ns2:srcVtag", $layer2_info)->[0]->getChildNodes()->[0]->getValue();
#    my $remoteTagZ = $xpath->find("./ns2:destVtag", $layer2_info)->[0]->getChildNodes()->[0]->getValue();

    my $remoteTagA = $xpath->find("./ns2:srcVtag", $layer2_info);
    if(!defined($remoteTagA->[0])){
        $remoteTagA = undef;
    }else{
        $remoteTagA = $remoteTagA->[0]->getChildNodes()->[0]->getValue();
    }

    my $remoteTagZ = $xpath->find("./ns2:destVtag", $layer2_info);
    if(!defined($remoteTagZ->[0])){
        $remoteTagZ = undef;
    }else{      
        $remoteTagZ = $remoteTagZ->[0]->getChildNodes()->[0]->getValue();
    }

    my @remote_endpoints;

    foreach my $remote_endpoint (({"node" => $remoteNodeA, "tag" => $remoteTagA},
				  {"node" => $remoteNodeZ, "tag" => $remoteTagZ})){

	my $remote_node = $remote_endpoint->{'node'};
	my $remote_tag  = $remote_endpoint->{'tag'};
	
	$remote_node =~ /domain=(\S+):node=(\S+):port=(\S+):link=(\S+)/;
	
	my $remote_domain = $1;
	my $remote_name   = $2;
	my $remote_port   = $3;
	my $remote_link   = $4;
	
	# don't need to double count endpoints we already know about locally
	next if ($remote_domain eq $LOCAL_DOMAIN);

	# it's remote so let's keep track of it
	push(@remote_endpoints, {"tag"  => $remote_tag,
	                         "urn"  => $remote_node});
    }

    # now let's go ahead and prep stuff to send in
    
    my $nodeA = $endpoints[0]->{'node'};
    my $intfA = $endpoints[0]->{'port'};
    my $tagA  = $endpoints[0]->{'tag'};

    my $nodeZ = $endpoints[1]->{'node'};
    my $intfZ = $endpoints[1]->{'port'};
    my $tagZ  = $endpoints[1]->{'tag'};

    $intfA =~ s/\+/ /g;
    $intfZ =~ s/\+/ /g;
    $nodeA =~ s/\+/ /g;
    $nodeZ =~ s/\+/ /g;
    
    my @links = keys %links;

    for(my $i=0;$i<$#links;$i++){
        $links[$i] =~ s/\+/ /g;
    }

    my @remote_nodes;
    my @remote_tags;

    foreach my $remote_endpoint (@remote_endpoints){
	my $remote_urn  = $remote_endpoint->{'urn'};
	my $remote_tag  = $remote_endpoint->{'tag'};
	push(@remote_nodes, $remote_urn);
	push(@remote_tags, $remote_tag);
    }    

    my $to_return = {"description"  => $description,
		     "bandwidth"    => $bandwidth,
		     "links"        => \@links,
		     "nodes"        => [$nodeA, $nodeZ],
		     "interfaces"   => [$intfA, $intfZ],
		     "tags"         => [$tagA, $tagZ],
		     "gri"          => $gri,
		     "remote_nodes" => \@remote_nodes,
		     "remote_tags"  => \@remote_tags,
		     "callback_url" => $callback_url
    };

    return $to_return;		
}

1;


