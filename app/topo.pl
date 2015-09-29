#!/usr/bin/perl
#
##----- D-Bus NDDI topo.pl
##-----
##----- $HeadURL$
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----
##----- Handles topology related events that appear over the dbus
#---------------------------------------------------------------------
#
# Copyright 2011 Trustees of Indiana University
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

use strict;

use Data::Dumper;
use OESS::Database;
use OESS::DBus;
use Net::DBus::Annotation qw(:call);
use Net::DBus::Exporter qw(org.nddi.openflow);
use Switch;
use Socket;
use Sys::Syslog qw(:standard :macros);
use English;
use Getopt::Long;
use Proc::Daemon;

use constant OFPPR_ADD => 0;
use constant OFPPR_DELETE => 1;
use constant OFPPR_MODIFY => 2;

my $dbus;
my $dbh;
my $db;
my $network_id=1;
my $default_latitude ="0.0";
my $default_longitude="0.0";
my $config_filename="/etc/oess/database.xml";
my $default_mtu=9000;
my $is_daemon=0;

#######################
#helpers
##############

sub handle_error{
    my $error = shift;
    print_log(LOG_ERR,$error);
    return;
}

sub print_log{
    my $priority=shift;
    my $message=shift;
    chomp($message);

    if(0==$is_daemon){
	return print STDERR "$message\n";
    }
    else{
	return syslog($priority,$message);
    }
}

sub datapath_join_to_db{
    my $dpid   = shift;
    my $ip     = shift;
    my $ports  = shift;

    my $node_db_id;
    my $node_admin_state;
    my $node_admin_ipv4;

    #step 0 -> begin transaction
    #steps 1. create new host if not there, if present then update state to available it state is planned.
    #step 2. -> get db interfaces,
    #step 3-> decom interfaces not present on the join.
    #step 4-> insert new interfaces, update the state if not there
    #step6 commit.
    #
    print_log(LOG_DEBUG,"Datapath Join event");
    $dbh->ping();

    $db->_start_transaction();
    my $node = $db->get_node_by_dpid(dpid => $dpid);
    my $node_id;
    if(defined($node)){
    #node exists
	print_log(LOG_DEBUG,"Node Exists");
	#update operational state to up
	$db->update_node_operational_state(node_id => $node->{'node_id'}, state => 'up');
        #update admin state if it is planned (now it exists and we have some data to back this assertion)
	if ( $node->{'admin_state'} =~ /planned/){
	    ##update old, create new
	    print_log(LOG_INFO, "updating state for node=" . $node->{'node_id'} . "\n");
	    $db->create_node_instance(node_id => $node->{'node_id'}, ipv4_addr => $ip ,admin_state => 'available',dpid => $dpid);
	}
	$node_id = $node->{'node_id'};

    }else{
	#insert and get the node_id
	print_log(LOG_DEBUG,"Adding a new Node!");
	my $node_name;
	my $addr = inet_aton($ip);
	# try to look up the name first to be all friendly like
	$node_name = gethostbyaddr($addr, AF_INET);

	# avoid any duplicate host names. The user can set this to whatever they want
	# later via the admin interface.
	my $i = 1;
	my $tmp = $node_name;
	while (my $result = $db->get_node_by_name(name => $tmp)){
	    $tmp = $node_name . "-" . $i;
	    $i++;
	}

	$node_name = $tmp;

	# default
	if (! $node_name){
	    $node_name="unnamed-".$dpid;
	}

	$node_id = $db->add_node(name => $node_name, operational_state => 'up', network_id => $network_id);
	if(!defined($node_id)){
	    $db->_rollback();
	    return;
	}
	$db->create_node_instance(node_id => $node_id, ipv4_addr => $ip, admin_state => 'available', dpid => $dpid);
    }

    foreach my $port (@$ports){
	next if $port->{'port_no#'} > (2 ** 12);

	my $operational_state = 'up';
	my $operational_state_num = (int($port->{'state'}) & 0x1);

	if(1== $operational_state_num ){
	    $operational_state='down';
	}
	my $admin_state = 'up';
	my $admin_state_num = (int($port->{'config'}) & 0x1);

	if(1 == $admin_state_num){
	    $admin_state = 'down';
	}

	my $int_id = $db->add_or_update_interface(node_id => $node_id,name => $port->{'name'}, description => $port->{'name'}, operational_state => $operational_state, port_num => $port->{'port_no'}, admin_state => $admin_state);

	if(!defined($int_id)){
	    $db->_rollback();
	    return undef;
	}

	#determine if any links are now down or unknown state
	my $link = $db->get_link_by_interface_id( interface_id => $int_id );
	if(defined($link) && defined($link->[0])){
	    $link = $link->[0];
	    if($operational_state eq 'up'){
		if($link->{'status'} eq 'up'){
		    #its up... and has been up...
		}else{
		    #wait for the link to be detected and then it will get set to up!
		    $db->update_link_state( link_id => $link->{'link_id'}, state => 'unknown' );
		}
	    }else{
		$db->update_link_state( link_id => $link->{'link_id'}, state => 'down');
	    }
	}else{
	    #no link on this interface...
	}

        #fire the topo_port_status_event
        _send_topo_port_status($dpid, OFPPR_ADD, $port);
    }

    $db->_commit();
}


sub datapath_join_callback{
	my $dpid   = shift;
	my $ip     = shift;
	my $ports  = shift;

	print_log(LOG_INFO,"DP JOIN: IP IS $ip\n");

        datapath_join_to_db($dpid,$ip,$ports);
}


sub datapath_leave_to_db{
    my $dpid = shift;

    $dbh->ping();
    my $node = $db->get_node_by_dpid(dpid => $dpid);
    my $interfaces = $db->get_node_interfaces( node => $node->{'name'} );
    $db->update_node_operational_state(node_id => $node->{'node_id'}, state => "down");

    #set the interfaces on the node to down
    foreach my $int (@$interfaces){

	$db->update_interface_operational_state( interface_id => $int->{'interface_id'},
						 operational_state => 'decom');

    }
}




sub datapath_leave_callback{
    my $dpid = shift;

    print_log(LOG_INFO,"DP LEAVE: dpid: $dpid");
    datapath_leave_to_db($dpid);

}

sub do_port_modify{
       my %args = (
	   @_,
        );
       my $dpid=$args{'dpid'};
       my $port_info=$args{'port_info'} ;

       $dbh->ping();

       $db->_start_transaction() or die $dbh->errstr;

       my $operational_state = 'up';
       my $operational_state_num=(int($port_info->{'state'}) & 0x1);
       if(1 == $operational_state_num){
           $operational_state = 'down';
       }

       my $admin_state = 'up';
       my $admin_state_num = (int($port_info->{'config'}) & 0x1);

       if(1 == $admin_state_num){
           $admin_state = 'down';
       }

       my $int = $db->get_interface_by_dpid_and_port(dpid => $dpid, port_number => $port_info->{'port_no'});
       if(!defined($int)){
	   #new interface!
	   my $node = $db->get_node_by_dpid( dpid => $dpid);

	   my $res = $db->add_or_update_interface(node_id => $node->{'node_id'}, name => $port_info->{'name'}, description => $port_info->{'name'}, operational_state => $operational_state, port_num => $port_info->{'port_no'}, admin_state => $admin_state);
	   print_log(LOG_ERR,"Added new interface!");
	   if(!defined($res)){
	       $db->_rollback();
	       return;
	   }
           $db->_commit();
           return;
       }

       #my $res = $db->update_interface_operational_state( operational_state => $operational_state, interface_id => $int->{'interface_id'});
       my $res = $db->add_or_update_interface(node_id => $int->{'node_id'}, name => $port_info->{'name'}, description => $port_info->{'name'}, operational_state => $operational_state, port_num => $port_info->{'port_no'}, admin_state => $admin_state);
       
       #check and see if there is a link and update the link status
       my $links = $db->get_link_by_interface_id( interface_id => $int->{'interface_id'} );
       if(defined($links)){
	   foreach my $link (@$links){
	       $db->update_link_state( link_id => $link->{'link_id'}, state => $operational_state);
	   }
       }

       $db->_commit();

}


sub db_port_status{
    my %args = @_;

    my $dpid=$args{'dpid'};
    my $reason=$args{'reason'};
    my $port_info=$args{'port_info'} ;

    switch($reason){
	case OFPPR_ADD 	  {
	    print_log(LOG_DEBUG, " adding port\n");
	    do_port_modify(dpid=> $dpid, port_info=>$port_info);
	    #fire the topo_port_status_event
	    _send_topo_port_status($dpid,$reason,$port_info);
	};
	case OFPPR_DELETE {
	    print_log(LOG_DEBUG, "deleting port\n");
	    do_port_modify(dpid => $dpid, port_info=>$port_info);
	};
	case OFPPR_MODIFY {
	    print_log(LOG_DEBUG,"modify port\n");
	    do_port_modify(dpid=>$dpid,port_info=>$port_info);
	};
    }
}


sub _send_topo_port_status{
    my $dpid = shift;
    my $reason = shift;
    my $info = shift;
    print_log(LOG_ERR, "Preparing to send topo_port_status event.");

    my $bus = Net::DBus->system;
    my $client;
    my $service;
    eval {
        $service = $bus->get_service("org.nddi.fwdctl");
        $client  = $service->get_object("/controller1");
    };
    if ($@){
        print_log(LOG_ERR, "Could not connect to DBus service org.nddi.fwdctl.");
        warn "Error in _connect_to_fwdctl: $@";
        return undef;
    }
    
    if (! defined $client) {
        print_log(LOG_ERR, "Couldn't get DBus object from org.nddi.fwdctl.");
        return undef;
    }
    
    print_log(LOG_ERR, "Sending topo_port_status event");
    eval {
        $client->topo_port_status(dbus_call_async, $dpid, $reason, $info);
    };
    if ($@) {
        print_log(LOG_ERR, "Dropped topo_port_status event: $@");
    } else {
        print_log(LOG_ERR, "Sent topo_port_status event.");
    }
}

sub port_status_callback{
	my $dpid   = shift;
	my $reason = shift;
	my $info   = shift;
	print_log(LOG_ERR, "port status: $dpid: $reason: ".Dumper($info));

        db_port_status(dpid=>$dpid,reason=>$reason,port_info=>$info);
}


sub get_active_link_id_by_connectors{
       my %args = @_;

        my $a_dpid  = $args{'a_dpid'};
        my $a_port  = $args{'a_port'};
        my $z_dpid  = $args{'z_dpid'};
        my $z_port  = $args{'z_port'};
        my $interface_a_id = $args{'interface_a_id'};
        my $interface_z_id = $args{'interface_z_id'};

       if(defined $interface_a_id){

       }else{
          $interface_a_id = $db->get_interface_by_dpid_and_port( dpid => $a_dpid, port_number => $a_port);
       }

       if(defined $interface_z_id){

       }else{
          $interface_z_id = $db->get_interface_by_dpid_and_port( dpid => $z_dpid, port_number => $z_port);
       }

       #find current link if any
       my $link = $db->get_link_by_a_or_z_end( interface_a_id => $interface_a_id, interface_z_id => $interface_z_id);
       print STDERR "Found LInk: " . Dumper($link);
       if(defined($link) && defined(@{$link})){
	   $link = @{$link}[0];
	   print STDERR "Returning LinkID: " . $link->{'link_id'} . "\n";
	   return ($link->{'link_id'},$link->{''});
       }

       return undef;
}


sub db_link_add{
    my %args = @_;
    my $a_dpid  = $args{'a_dpid'};
    my $a_port  = $args{'a_port'};
    my $z_dpid  = $args{'z_dpid'};
    my $z_port  = $args{'z_port'};

    $dbh->ping();
    $db->_start_transaction();

    my $interface_a = $db->get_interface_by_dpid_and_port( dpid => $a_dpid, port_number => $a_port);
    my $interface_z = $db->get_interface_by_dpid_and_port( dpid => $z_dpid, port_number => $z_port);

    if(!defined($interface_a) || !defined($interface_z)){
	print_log(LOG_ERR,"Either the A or Z endpoint was not found in the database while trying to add a link");
	$db->_rollback();
	return undef;
    }

    #find current link if any
    my ($link_db_id, $link_db_state) = get_active_link_id_by_connectors( interface_a_id => $interface_a->{'interface_id'}, interface_z_id => $interface_z->{'interface_id'} );

    if($link_db_id){
	##up the state?
	print_log(LOG_DEBUG,"Link already exists, setting to up");
	$db->update_link_state( link_id => $link_db_id, state => 'up');
        $db->_commit();
    }else{
	#first determine if any of the ports are currently used by another link... and connect to the same other node
	my $links_a = $db->get_link_by_interface_id( interface_id => $interface_a->{'interface_id'}, show_decom => 0);
	my $links_z = $db->get_link_by_interface_id( interface_id => $interface_z->{'interface_id'}, show_decom => 0);

	my $z_node = $db->get_node_by_id( node_id => $interface_z->{'node_id'} );
	my $a_node = $db->get_node_by_id( node_id => $interface_a->{'node_id'} );

	my $a_links;
	my $z_links;

	#lets first remove any circuits not going to the node we want on these interfaces
	foreach my $link (@$links_a){
	    my $other_int = $db->get_interface( interface_id => $link->{'interface_a_id'} );
	    if($other_int->{'interface_id'} == $interface_a->{'interface_id'}){
		$other_int = $db->get_interface( interface_id => $link->{'interface_z_id'} );
	    }

	    my $other_node = $db->get_node_by_id( node_id => $other_int->{'node_id'} );
	    if($other_node->{'node_id'} == $z_node->{'node_id'}){
		push(@$a_links,$link);
	    }
	}

	foreach my $link (@$links_z){
	    my $other_int = $db->get_interface( interface_id => $link->{'interface_a_id'} );
            if($other_int->{'interface_id'} == $interface_z->{'interface_id'}){
                $other_int = $db->get_interface( interface_id => $link->{'interface_z_id'} );
            }
            my $other_node = $db->get_node_by_id( node_id => $other_int->{'node_id'} );
            if($other_node->{'node_id'} == $a_node->{'node_id'}){
		push(@$z_links,$link);
            }
	}


	#ok... so we now only have the links going from a to z nodes
	# we pretty much have 4 cases... there are 2 or more links going from a to z
	# there is 1 link going from a to z (this is enumerated as 2 elsifs one for each side)
	# there is no link going from a to z
	if(defined($a_links->[0]) && defined($z_links->[0])){
	    #ok this is the more complex one to worry about
	    #pick one and move it, we will have to move another one later
	    my $link = $a_links->[0];
	    my $old_z = $link->{'interface_a_id'};
	    if($old_z == $interface_a->{'interface_id'}){
		$old_z = $link->{'interface_z_id'};
	    }
	    my $old_z_interface = $db->get_interface( interface_id => $old_z);
	    $db->decom_link_instantiation( link_id => $link->{'link_id'} );
	    $db->create_link_instantiation( link_id => $link->{'link_id'}, interface_a_id => $interface_a->{'interface_id'}, interface_z_id => $interface_z->{'interface_id'}, state => $link->{'state'} );
	    $db->_commit();
	    #do admin notify


	    #diff the interfaces
	    _send_topo_port_status($z_node->{'dpid'},OFPPR_ADD,{name => $interface_z->{'name'}, port_no => $interface_z->{'port_number'}, link => 1});
	    _send_topo_port_status($z_node->{'dpid'},OFPPR_ADD,{name => $interface_z->{'name'}, port_no => $old_z_interface->{'port_number'}, link => 1});

	}elsif(defined($a_links->[0])){
	    print_log(LOG_WARNING,"LINK has changed interface on z side");
	    #easy case update link_a so that it is now on the new interfaces
	    my $link = $a_links->[0];
	    my $old_z =$link->{'interface_a_id'};
	    if($old_z == $interface_a->{'interface_id'}){
		$old_z = $link->{'interface_z_id'};
            }
            my $old_z_interface= $db->get_interface( interface_id => $old_z);
	    #if its in the links_a that means the z end changed...
	    $db->decom_link_instantiation( link_id => $link->{'link_id'} );
	    $db->create_link_instantiation( link_id => $link->{'link_id'}, interface_a_id => $interface_a->{'interface_id'}, interface_z_id => $interface_z->{'interface_id'}, state => $link->{'state'} );
	    $db->_commit();
	    #do admin notification


	    #diff the z node
	    _send_topo_port_status($z_node->{'dpid'},OFPPR_ADD,{name => $interface_z->{'name'}, port_no => $interface_z->{'port_number'}, link => 1});
            _send_topo_port_status($z_node->{'dpid'},OFPPR_ADD,{name => $interface_z->{'name'}, port_no => $old_z_interface->{'port_number'}, link => 1});

	}elsif(defined($z_links->[0])){
            #easy case update link_a so that it is now on the new interfaces
	    print_log(LOG_WARNING,"Link has changed ports on the A side");
	    my $link = $z_links->[0];

	    my $old_a =$link->{'interface_a_id'};
            if($old_a == $interface_z->{'interface_id'}){
                $old_a = $link->{'interface_z_id'};
            }
            my $old_a_interface= $db->get_interface( interface_id => $old_a);

	    $db->decom_link_instantiation( link_id => $link->{'link_id'});
	    $db->create_link_instantiation( link_id => $link->{'link_id'}, interface_a_id => $interface_a->{'interface_id'}, interface_z_id => $interface_z->{'interface_id'}, state => $link->{'state'});
	    $db->_commit();
	    #do admin notification

	    #diff the interfaces
            #diff the a node
            _send_topo_port_status($a_node->{'dpid'},OFPPR_ADD,{name => $interface_a->{'name'}, port_no => $interface_a->{'port_number'}, link => 1});
            _send_topo_port_status($a_node->{'dpid'},OFPPR_ADD,{name => $old_a_interface->{'name'}, port_no => $old_a_interface->{'port_number'}, link => 1});
	}else{
	    print_log(LOG_WARNING,"This is not part of any other link... making a new instance");
	    ##create a new one link as none of the interfaces were part of any link
	    print_log(LOG_DEBUG,"Adding a new link");

	    my $link_name = "auto-" . $a_dpid . "-" . $a_port . "--" . $z_dpid . "-" . $z_port;
	    my $link = $db->get_link_by_name(name => $link_name);
	    my $link_id;

	    if(!defined($link)){
		$link_id = $db->add_link( name => $link_name );
	    }else{
		$link_id = $link->{'link_id'};
	    }

	    if(!defined($link_id)){
		print_log(LOG_ERR,"Unable to add link!");
		$db->_rollback();
		return undef;
	    }

	    $db->create_link_instantiation( link_id => $link_id, state => 'available', interface_a_id => $interface_a->{'interface_id'}, interface_z_id => $interface_z->{'interface_id'});
	    $db->_commit();
	}
    }

}

sub link_event_to_db{
    my %args = @_;
    my $a_dpid  = $args{'a_dpid'};
    my $a_port  = $args{'a_port'};
    my $z_dpid  = $args{'z_dpid'};
    my $z_port  = $args{'z_port'};
    my $status  = $args{'status'};
    switch($status){
	case "add"{

	    print_log(LOG_INFO, "add event\n");
	    db_link_add(a_dpid=>$a_dpid, a_port=>$a_port, z_dpid=>$z_dpid, z_port=>$z_port);

	}case "remove"{

	    print_log(LOG_INFO, "down event however we don't do anything with this...\n");
	    my $interface_a = $db->get_interface_by_dpid_and_port( dpid => $a_dpid, port_number => $a_port);
	    my $interface_z = $db->get_interface_by_dpid_and_port( dpid => $z_dpid, port_number => $z_port);
	    my ($link_id, $link_state) = get_active_link_id_by_connectors( interface_a_id => $interface_a->{'interface_id'}, interface_z_id => $interface_z->{'interface_id'} );
	    if($interface_a->{'state'} eq 'up' && $interface_z->{'state'} eq 'up'){
#		$db->update_link_state( link_id => $link_id, state => 'unknown');
	    }else{
#		$db->update_link_state( link_id => $link_id, state => 'down');
	    }

	}else{

	    print_log(LOG_NOTICE, "Do not know how to handle $status link event\n");

	}
    }
}


sub link_event_callback{
	my $a_dpid  = shift;
	my $a_port  = shift;
	my $z_dpid  = shift;
	my $z_port  = shift;
	my $status  = shift;
	print STDERR "link event: $a_dpid / $a_port to $z_dpid / $z_port is $status\n";
	print_log(LOG_DEBUG, "link event: $a_dpid / $a_port to $z_dpid / $z_port is $status\n");
        link_event_to_db(a_dpid=>$a_dpid, a_port=>$a_port, z_dpid=>$z_dpid, z_port=>$z_port,status=>$status);
}

sub packet_in_callback{
        my $dpid    = shift;
	my $in_port = shift;
        my $reason  = shift;
 	my $length  = shift;
	my $buff_id = shift;
	my $data    = shift;
        print_log(LOG_DEBUG, "packet_in: $dpid / $in_port: $reason , $length, $buff_id:".Dumper($data));;
}

sub flow_mod_callback{
        my $dpid   = shift;
	my $attrs  = shift;
	my $command= shift;
	my $idleto = shift;
	my $hardto = shift;
	my $buff_id= shift;
	my $pri    = shift;
	my $cookie = shift;
        print_log(LOG_DEBUG, "flow_mod $dpid: $command:$idleto,$hardto ".Dumper($attrs));
}

sub flow_removed_callback{
	my $dpid   = shift;
        my $attrs  = shift;
	my $pri	   = shift;
	my $reason = shift;
	my $cookie = shift;
        my $dursec = shift;
        my $durnsec= shift;
        my $bytecnt= shift;
        my $packcnt= shift;
	print_log(LOG_DEBUG, "flow_removed: $dpid: $reason: $pri: $cookie: $dursec,$durnsec,$bytecnt,$packcnt: ".Dumper($attrs));
}

sub core{

   $db  = OESS::Database->new(config => $config_filename) or die();
   $dbh = $db->{'dbh'};
   if (not defined $dbh){
      print_log(LOG_ERR,"cannot connect to the database\n");
      return;
   }
    
   #get current nodes
    my $nodes = $db->get_current_nodes();
    foreach my $node (@$nodes) {

        $db->update_node_operational_state(node_id => $node->{'node_id'}, state => 'down');

    }

   #set operational status to 'down';   

   $dbus = OESS::DBus->new( service => "org.nddi.openflow", instance => "/controller1", timeout => -1, sleep_interval => .1);
   if(defined($dbus)){
       my $sig;
       #--- topo events
       $sig = $dbus->connect_to_signal("datapath_join",\&datapath_join_callback);
       $sig = $dbus->connect_to_signal("datapath_leave",\&datapath_leave_callback);
       $sig = $dbus->connect_to_signal("port_status",\&port_status_callback);
       $sig = $dbus->connect_to_signal("link_event",\&link_event_callback);

       $dbus->start_reactor();
   }else{
       syslog(LOG_ERR,"Unable to connect to DBus");
       die;
   }

}



sub main(){

    my $verbose;
    my $username;
    my $result = GetOptions ( #"length=i" => \$length, # numeric
                           #"file=s" => \$data, # string
                           "user|u=s" => \$username,
                           "verbose" => \$verbose, #flag
                           "daemon|d" => \$is_daemon,
                         );
    if (0!=$is_daemon){
         openlog("topo.pl", 'cons,pid', LOG_DAEMON);

    }
    #now change username/
    if(defined $username){
       my $new_uid=getpwnam($username);
       my $new_gid=getgrnam($username);
       $EGID=$new_gid;
       $EUID=$new_uid;
    }

    $SIG{'CHLD'} = 'CHLD_handler';

    if (0!=$is_daemon){
        my $daemon;
        if($verbose){
            $daemon = Proc::Daemon->new(
                pid_file => '/var/run/oess/topo.pid',
                child_STDOUT => '/var/log/oess/topo.out',
                child_STDERR => '/var/log/oess/topo.log',
                );
        }else{
            $daemon = Proc::Daemon->new(
                pid_file => '/var/run/oess/topo.pid'
                );
        }

       my $kid = $daemon->Init;

       unless( $kid){
          $SIG{'CHLD'}= undef;
          core(); #core should never return
          print_log(LOG_ERR,"abnormal exit");
          die();
       }
       #this is the parent process
       `chmod 0644 /var/run/oess/topo.pid`;
       sleep(2);
       if (0 == $daemon->Status()){
         die(); ##exit failure
       }
       exit(0);

    }
    else{
      #now a deamon, just run the core;
	$SIG{HUP} = sub{ exit(0); };
      core();
    }


    #print_log(LOG_DEBUG, "is_daemon =$is_daemon\n");
    #wern "hello\n";
    #core();
}


main();
