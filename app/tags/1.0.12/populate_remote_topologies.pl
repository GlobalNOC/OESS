#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use JSON;

use OESS::Database;
use XML::XPath;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Headers;
use URI::Escape;

use URI::Escape;

my $db;

sub main{

    $db = OESS::Database->new();

    my $topology = get_remote_topology();
    process_topology($topology);

}



sub get_remote_topology {
    my $results;
    
    my $PS_TS = $db->get_oscars_topo();
    my $LOCAL_DOMAIN = $db->get_local_domain_name();
    my $workgroup_id = 1;
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
    
    
    my $ua = LWP::UserAgent->new ('timeout' => ( 30 * 1000));
    my $messg = HTTP::Request->new('POST',$PS_TS , new HTTP::Headers, $message);
    $messg->header( 'SOAPAction' => "http://ggf.org/ns/nmwg/base/2.0/message/");
    $messg->content_type('text/xml');
    $messg->content_length( length($message));
    my $resp = $ua->request($messg);
    my $respContent;
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
			    
			    if (defined($is_local) && $is_local == 1){

                            my $auth = $db->_execute_query("select 1 from workgroup_interface_membership " .
                                                           " join interface on interface.interface_id = workgroup_interface_membership.interface_id " .
                                                           " join node on node.node_id = interface.node_id " .
                                                           " where workgroup_id = ? and interface.name = ? and node.name = ?",
                                                           [$workgroup_id, $port_name, $node_name]);

                            # didn't find a membership, skip this
                            next if ($auth && @$auth < 1);
			    }

			}

			push(@links,{urn        => $link,
                                 node       => $node_name,
                                 port       => $port_name ,
                                 link       => $link_name,
                                 remote_urn => $remote_link_urn,
				     latitude   => $latlong->{'latitude'},
				     longitude  => $latlong->{'longitude'}
			     });

		    }
		}
	    }

	    @links = sort {
		if ($a->{'node'} eq $b->{'node'}){
		    return $a->{'port'} cmp $b->{'port'};
		}
		return $a->{'node'} cmp $b->{'node'};
	    } @links;

	    push(@domains,{ name => $domain_name, urn => $domain, links => \@links});
	}

	@domains = sort { $a->{'name'} cmp $b->{'name'} } @domains;
	return {'results' => \@domains};
    }
    else{
        return {'error' => 'Error retreiving remote topologies'};
    }
}


sub process_topology{
    my $topology = shift;
    
    my $LOCAL_DOMAIN = $db->get_local_domain_name();

    if (! $LOCAL_DOMAIN){
	die "Error - could not determine local domain. Is database set up properly?";
    }
    
    
    my $struct = $topology;
    
    $db->_start_transaction();
    
    foreach my $domain_info (@{$struct->{'results'}}){
	
	my $domain = $domain_info->{'name'};
	
	my $network_id = &add_network($domain);
	
	my $links  = $domain_info->{'links'};
	
	foreach my $link (@$links){
	    
	    my $link_name  = uri_unescape($link->{'link'});
	    my $link_urn   = uri_unescape($link->{'urn'});
	    my $node_name  = uri_unescape($link->{'node'});
	    my $port       = uri_unescape($link->{'port'});
	    my $remote_urn = uri_unescape($link->{'remote_urn'});	
	    
	    &add_link($link_name, $link_urn, $node_name, $port, $remote_urn, $domain, $network_id);
	    
	};
	
    }
    
    $db->_commit();
}


sub add_link {
    my $link       = shift;
    my $urn        = shift;
    my $node       = shift;
    my $port       = shift;
    my $remote_urn = shift;
    my $local_domain = shift;
    my $network_id = shift;

    # figure out if node exists

    my $results = $db->_execute_query("select * from node where name = ? and network_id = ?", [$node, $network_id]);

    my $node_id;

    if (@$results > 0){
	$node_id = @$results[0]->{'node_id'};
	#ignore nodes that are part of our local network
	next if(@$results[0]->{'network_id'} == 1);
    }
    else {
	$node_id = $db->_execute_query("insert into node (name, longitude, latitude, operational_state, network_id) values (?, ?, ?, ?, ?)",
				       [$node, 0, 0, "unknown", $network_id]
	    ) or die "Couldn't create node";
    }

    

    # figure out the interface

    # we might have this interface before but didn't know about the URN, we can update it now
    $results = $db->_execute_query("select * from interface where node_id = ? and name = ? ",  [$node_id, $port]);
    my $interface_id;
    if(@$results > 0){
        $interface_id=@$results[0]->{'interface_id'};
    }else{
        #insert the interface
        $results=$db->_execute_query("insert into interface (name, description, operational_state, role, node_id) values (?, ?, ?, ?, ?)",
                                            [$port, $port, "unknown", "unknown", $node_id]) or die "Couldn't create interface";
        $results = $db->_execute_query("select * from interface where node_id = ? and name = ? ",  [$node_id, $port]);
        if(@$results > 0){
           $interface_id=@$results[0]->{'interface_id'};
        }
    }
    #insert the urn with ignore!
    $results=$db->_execute_query("insert ignore into urn (urn, interface_id, last_update) values (?, ?, ?)",
                                            [$urn, $interface_id, time() ]);
    


    # urn:ogf:network:domain=nddi.net.internet2.edu:node=switch%202:port=s2-eth1:link=auto-3%3A2--2%3A1
    $urn =~ s/\n\s*//g;
    $remote_urn =~ s/\n\s*//g;

    $urn =~ /domain=(.+):node=(.+):port=(.+):link=(\S+)/;

    my $local_node = $2;
    my $local_port = $3;
    my $local_link = $4;

    $remote_urn =~ /domain=(.+):node=(.+):port=(.+):link=(\S+)/;
    
    my $remote_domain = $1;
    my $remote_node   = $2;
    my $remote_port   = $3;
    my $remote_link   = $4;

    # we don't care about intra domain links here, only inter
    return if ($remote_domain eq $local_domain);    

    # figure out the link if applicable
    $results = $db->_execute_query("select * from link where name = ?", [$urn]);
    
    # new link, figure out how to hook it up   
    if (@$results < 1){	

	$results = $db->_execute_query("select interface.interface_id from interface join node on node.node_id = interface.node_id join network on network.network_id = node.network_id " .
				       " left join urn on urn.interface_id=interface.interface_id ".
				       " where node.name = ? and network.name = ? and interface.name = ? and urn.urn = ?",
				       [$remote_node, $remote_domain, $remote_port, $remote_urn]);

	if (@$results > 0){

	    my $interface_z = @$results[0]->{'interface_id'};

	    my $link_id = $db->_execute_query("insert into link (name, remote_urn) values (?, ?)", [$urn, $remote_urn]) or die "Couldn't create link";

	    my $inst_result = $db->_execute_query("insert into link_instantiation (link_id, end_epoch, start_epoch, interface_a_id, interface_z_id, link_state) values (?, ?, ?, ?, ?, ?)",
						  [$link_id, -1, "UNIX_TIMETSTAMP(NOW())", $interface_id, $interface_z, "active"]);

	    die "Couldn't create link instantiation" if (! defined $inst_result);
	}

    }

}


sub add_network {

    my $domain = shift;

    my $results = $db->_execute_query("select * from network where name = ?", [$domain]);

    if (@$results > 0){
	return @$results[0]->{'network_id'};
    }

    return $db->_execute_query("insert into network (name, longitude, latitude, is_local) values (?, 0, 0, 0)", [$domain]) or die "Can't create network";

}


main();
