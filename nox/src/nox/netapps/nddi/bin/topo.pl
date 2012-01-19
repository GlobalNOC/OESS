#!/usr/bin/perl
#--------------------------------------------------------------------
#----- D-Bus NDDI  test client 
#-----
#----- $HeadURL:
#----- $Id:
#-----
#----- Listens to all events sent on org.nddi.openflow.events 
#---------------------------------------------------------------------
#
# Copyright 2011 Trustees of Indiana University 
# 
#   Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
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
use Net::DBus;
use Net::DBus::Dumper;
use Net::DBus::Reactor;
use Data::Dumper;


  
sub datapath_join_callback{
	my $dpid   = shift;
	my $ports  = shift;
	print "datapath_join: $dpid = ".Dumper($ports);
}

sub port_status_callback{
	my $dpid   = shift;
	my $reason = shift;
	my $info   = shift;
	print "port status: $dpid: $reason: ".Dumper($info);
}

sub link_event_callback{
	my $a_dpid  = shift;
	my $a_port  = shift;
	my $z_dpid  = shift;
	my $z_port  = shift;
	my $status  = shift;
	print "link event: $a_dpid / $a_port to $z_dpid / $z_port is $status\n";
}

sub packet_in_callback{
        my $dpid    = shift;
	my $in_port = shift; 
        my $reason  = shift;
 	my $length  = shift;
	my $buff_id = shift;
	my $data    = shift;
        print "packet_in: $dpid / $in_port: $reason , $length, $buff_id:".Dumper($data);
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
        print "flow_mod $dpid: $command:$idleto,$hardto ".Dumper($attrs);
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
	print "flow_removed: $dpid: $reason: $pri: $cookie: $dursec,$durnsec,$bytecnt,$packcnt: ".Dumper($attrs);
}
	


sub connect_to_object{
   my $service   = shift;
   my $obj_name  = shift;
  
   my $obj;
   while(1){
      eval{	
         my $bus = Net::DBus->system;
         my $srv = undef;
         $srv = $bus->get_service($service);
         $obj = $srv->get_object($obj_name);
      };
     if($@){
	#--- error
	warn "dbus connection error: $@ ... retry in few\n";
	sleep 2;
     }else{
        #--- success
	return $obj;
     }
   }
}


my $obj = connect_to_object("org.nddi.openflow","/controller1");

my $sig;
#--- topo events
$sig = $obj->connect_to_signal("datapath_join",\&datapath_join_callback);
$sig = $obj->connect_to_signal("port_status",\&port_status_callback);
$sig = $obj->connect_to_signal("link_event",\&link_event_callback);

#--- flow events
#$sig = $obj->connect_to_signal("packet_in",\&packet_in_callback);
$sig = $obj->connect_to_signal("flow_mod",\&flow_mod_callback);
$sig = $obj->connect_to_signal("flow_removed",\&flow_removed_callback);


#--- this is a standard reactor pattern, callbacks are fired 
#--- as events happen
my $reactor = Net::DBus::Reactor->main();

$reactor->add_timeout(10000, sub {
      print "heartbeat...\n";
      #--- $reactor->shutdown();
});

$reactor->run();
print "exiting...\n";

