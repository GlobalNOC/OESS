#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use JSON;

use OESS::Database;

use URI::Escape;

my $db = OESS::Database->new();

my $LOCAL_DOMAIN = $db->get_local_domain_name();

if (@ARGV < 1){
    die "usage: $0 <file to parse>";
}

if (! $LOCAL_DOMAIN){
    die "Error - could not determine local domain. Is database set up properly?";
}


open(OUTPUT, $ARGV[0]) or die "couldn't open $ARGV[0] for reading: $!";

my $lines = <OUTPUT>;

close(OUTPUT);

my $struct = decode_json($lines);

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


