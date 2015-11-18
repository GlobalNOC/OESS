#!/usr/bin/perl
#------ NDDI OESS Forwarding Control
##-----
##----- $HeadURL:
##----- $Id:
##-----
##----- Listens to all events sent on org.nddi.openflow.events
##---------------------------------------------------------------------
##
## Copyright 2013 Trustees of Indiana University
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

use OESS::DBus;
use OESS::FWDCTL::Master;
use Net::DBus::Exporter qw(org.nddi.fwdctl);
use Net::DBus qw(:typing);
use base qw(Net::DBus::Object);
use AnyEvent::DBus;
use English;
use Getopt::Long;
use Proc::Daemon;
use Data::Dumper;

#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;

#circuit statuses
use constant OESS_CIRCUIT_UP    => 1;
use constant OESS_CIRCUIT_DOWN  => 0;
use constant OESS_CIRCUIT_UNKNOWN => 2;

use strict;

my $log;

my $pid_file = "/var/run/oess/fwdctl.pid";

sub build_cache{

    my %cache;

    my $db = OESS::Database->new();
    my $circuits = $db->get_current_circuits();
        
    foreach my $circuit (@$circuits) {
	my $id = $circuit->{'circuit_id'};
	my $ckt = OESS::Circuit->new( db => $db,
				      circuit_id => $id );

	$cache{'circuit'}{$ckt->get_id()} = $ckt;
	my $operational_state = $circuit->{'details'}->{'operational_state'};
	if ($operational_state eq 'up') {
	    $cache{'circuit_status'}{$id} = OESS_CIRCUIT_UP;
	} elsif ($operational_state  eq 'down') {
	    $cache{'circuit_status'}{$id} = OESS_CIRCUIT_DOWN;
	} else {
	    $cache{'circuit_status'}{$id} = OESS_CIRCUIT_UNKNOWN;
	}
    }
        
    my $links = $db->get_current_links();
    foreach my $link (@$links) {
	if ($link->{'status'} eq 'up') {
	    $cache{'link_status'}{$link->{'name'}} = OESS_LINK_UP;
	} elsif ($link->{'status'} eq 'down') {
	    $cache{'link_status'}{$link->{'name'}} = OESS_LINK_DOWN;
	} else {
	    $cache{'link_status'}{$link->{'name'}} = OESS_LINK_UNKNOWN;
	}
    }
        
    my $nodes = $db->get_current_nodes();
    foreach my $node (@$nodes) {
	my $details = $db->get_node_by_dpid(dpid => $node->{'dpid'});
	$details->{'dpid_str'} = sprintf("%x",$node->{'dpid'});
	$details->{'name'} = $node->{'name'};
	$cache{'node_info'}{$node->{'dpid'}} = $details;
    }

    return \%cache;

}

sub core{
    my $cache = shift;

    Log::Log4perl::init_and_watch('/etc/oess/logging.conf',10);
    $log = Log::Log4perl->get_logger("FWDCTL");

    my $bus = Net::DBus->system;
    my $service = $bus->export_service("org.nddi.fwdctl");

    my $srv_object = OESS::FWDCTL::Master->new(service => $service, cache => $cache);

    my $dbus = OESS::DBus->new( service => "org.nddi.openflow", instance => "/controller1", timeout => -1, sleep_interval => .1);
    #--- listen for topo events ----
    sub datapath_join_callback{
        my $dpid   = shift;
        my $ports  = shift;
        my $dpid_str  = sprintf("%x",$dpid);
        $srv_object->datapath_join_handler($dpid);
    }

    sub port_status_callback{
        my $dpid   = shift;
        my $reason = shift;
        my $info   = shift;
        $srv_object->port_status($dpid,$reason,$info);
    }


    sub check_child_status{
        $srv_object->check_child_status();
    }

    sub link_event_callback{
        my $a_dpid  = shift;
        my $a_port  = shift;
        my $z_dpid  = shift;
        my $z_port  = shift;
        my $status  = shift;
        $srv_object->link_event($a_dpid,$a_port,$z_dpid,$z_port,$status);
    }

    sub reap_stale_events{
        $srv_object->reap_old_events();
    }


    $dbus->connect_to_signal("datapath_join",\&datapath_join_callback);
    $dbus->connect_to_signal("port_status",\&port_status_callback);
    $dbus->connect_to_signal("link_event",\&link_event_callback);


    my $timer = AnyEvent->timer( after => 10, interval => 10, cb => \&check_child_status);
    my $reaper = AnyEvent->timer( after => 3600, interval => 3600, cb => \&reap_stale_events);

    $srv_object->_sync_database_to_network();

    AnyEvent->condvar->recv;

}

sub main{
    my $is_daemon = 0;
    my $verbose;
    my $username;

    #--- see if the pid file exists. if not then just continue running.
    if(-e $pid_file){
        #--- read the file to get the PID
        my $pid = `head -n 1 $pid_file`;
        chomp $pid;

        my $run_test = `ps -p $pid | grep $pid`;

        #--- if run test is empty then the pid didn't exist. If it isn't empty then the process is already running.
        if($run_test){
            print "Found $0 process: $pid already running. Aborting.\n";
            exit(0);
        }
        else{
            print "Pid File: $pid_file already exists but it looks like process $pid is dead. Continuing startup.\n";
        }
    }

    my $result = GetOptions (
                             "user|u=s"  => \$username,
                             "verbose"   => \$verbose,
                             "daemon|d"  => \$is_daemon,
                            );


    #now change username/
    if (defined $username) {
        my $new_uid=getpwnam($username);
        my $new_gid=getgrnam($username);
        $EGID=$new_gid;
        $EUID=$new_uid;
    }

    if ($is_daemon != 0) {
        my $daemon;
        if ($verbose) {
            $daemon = Proc::Daemon->new(
                                        pid_file => $pid_file,
                                        child_STDOUT => '/var/log/oess/fwdctl.out',
                                        child_STDERR => '/var/log/oess/fwdctl.log',
                                       );
        } else {
            $daemon = Proc::Daemon->new(
                                        pid_file => $pid_file
                                       );
        }

	my $cache = build_cache();
	
        my $kid_pid = $daemon->Init;
	
        if ($kid_pid) {
            `chmod 0644 $pid_file`;
            return;
        }

	core($cache);
    }
    #not a deamon, just run the core;
    else {
        $SIG{HUP} = sub{ exit(0); };
	my $cache = build_cache();
	core($cache);
    }

}

main();

1;
