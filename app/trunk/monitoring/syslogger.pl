#!/usr/bin/perl

#Copyright ????


use strict;
use English;
use Proc::Daemon;
use OESS::Database;
use OESS::DBus;
use Net::DBus qw(:typing);
use Data::Dumper;
use Sys::Syslog qw(:standard :macros);
use Getopt::Long;
use OESS::Syslogger;
#these are part of the OpenFlow spec
#they are the reason for the port change
use constant OFPPR_ADD => 0;
use constant OFPPR_DELETE => 1;
use constant OFPPR_MODIFY => 2;

my $oess;
my $db;

=head2 port_status

This is the callback for the port_status event over Net::DBus

It takes a dpid, reason (int) and info (basically all the info about the event), and generates
syslogs for every 'active' port/circuit/link that is affected

It syslogs at LOG_ERR

=cut

sub port_status{
    my $dpid = shift;
    my $reason = shift;
    my $info = shift;

    #pull the needed info out
    my $port_name = $info->{'name'};
    my $port_number = $info->{'port_no'};
    my $link_status = $info->{'link'};

    #find the node based on the dpid
    my $node = $db->get_node_by_dpid( dpid => $dpid);
    if(!defined($node)){
	#woops... no node found?
	syslog(LOG_DEBUG,"No node found with dpid => $dpid");
	return;
    }
    
    #what is the current status
    my $status;
    if(!$link_status){
	$status = "down";
    }else{
	$status = "up";
    }

    #figure out our REASON and make it human readible
    if($reason == OFPPR_ADD){
	$reason = 'Port was added';
    }elsif($reason == OFPPR_DELETE){
	$reason = 'Port was deleted';
    }elsif($reason == OFPPR_MODIFY){
	$reason = 'Port was modified';
    }

    #first we want to syslog that the port changed status
    syslog(LOG_ERR,"PORT STATUS CHANGE: node " . $node->{'name'} . ":" . $node->{'node_id'} . ", port $port_number is $status reason:$reason");
    
    #try and find any links that go over this port
    my $link_info = $db->get_link_by_dpid_and_port(dpid => $dpid,
						   port => $port_number);

    if(!defined($link_info) || @$link_info < 1){
	#no links? we are done
	syslog(LOG_DEBUG,"No links affected by dpid: $dpid, port_no: $port_number going down");
	return;
    }

    $link_info = $link_info->[0];
    
    #log the even for the link
    syslog(LOG_ERR,"LINK STATUS CHANGE: " . $link_info->{'name'} . ":" . $link_info->{'link_id'} . " is $status reason:$reason");

    #try and find any circuits that ride over this link
    my $affected_circuits = $db->get_affected_circuits_by_link_id(link_id => $link_info->{'link_id'});
    if(!defined($affected_circuits) || @$affected_circuits < 1){
	#no circuits so we are done
	syslog(LOG_DEBUG,"No circuits for link: " . $link_info->{'link_id'});
	return;
    }

    
    #for every circuit we found, log the event
    foreach my $circuit_info (@$affected_circuits){
	my $circuit_id = $circuit_info->{'id'};
	my $circuit_name = $circuit_info->{'name'};
	syslog(LOG_ERR,"CIRCUIT STATUS CHANGE: $circuit_name:$circuit_id is $status reason:$reason");

    }
}

=head2 circuit_create callback

This is called when the webservice provisions a new circuit or schedules a new circuit to be provisioned.

=cut

sub circuit_create{

	#                 circuit_id    => $output->{'circuit_id'},
	#                 workgroup_id  => $output->{'workgroup_id'},
	#                 name          => $circuit_details->{'name'},
    #                 description   => $description,
    #                 circuit_state => $circuit_details->{'circuit_state'}

	my $circuit = shift;
	my $circuit_name= $circuit->{'name'};
	my $circuit_id = $circuit->{'id'};
	my $status = $circuit->{'circuit_state'};  

	syslog(LOG_ERR,"CIRCUIT Created: $circuit_name:$circuit_id in $status state");


}

=head2 circuit_modify callback

This is called at the time of a modified circuit

=cut

sub circuit_modify{


}

=head2 circuit_decomision callback

This is called at the time when a circuit is decomissioned

=cut

sub circuit_decomission{


}




=head2 datapath_join callback

This is called when a node joins the controller.  It sends more than just a dpid, but we only care about the dpid

logs at LOG_ERR

=cut


sub datapath_join{
    my $dpid = shift;
        
    my $node = $db->get_node_by_dpid( dpid => $dpid);
    if(!defined($node)){
	#we haven't seen this node before so do nothing
	syslog(LOG_DEBUG,"No Node found with dpid => $dpid");
	return;
    }
    
    #if the node isn't active then we don't really care if it goes up or down
    if($node->{'admin_state'} eq 'active'){
	syslog(LOG_ERR,"NODE STATUS CHANGE: " . $node->{'name'} . ":" . $node->{'node_id'} . " is up");
    }else{
	syslog(LOG_DEBUG,"node not active, ignoring for monitoring");
    }

}

=head2 datapath_leave

This is called when a node leaves the controller, the dpid should exist in the oess DB

it syslogs the event at LOG_ERR if the node is suppose to be active

=cut

sub datapath_leave{
    my $dpid = shift;

    my $node = $db->get_node_by_dpid( dpid => $dpid);
    if(!defined($node)){
	#hmm... we haven't seen this node before?
        syslog(LOG_DEBUG,"No Node found with dpid => $dpid");
        return;
    }

    #if the node isn't active then we don't really care if it goes up or down
    if($node->{'admin_state'} eq 'active'){
	syslog(LOG_ERR,"NODE STATUS CHANGE: ". $node->{'name'} . ":". $node->{'node_id'} . " is down");
    }else{
	syslog(LOG_DEBUG,"node not active, ignoring for monitoring");
    }
    
}


#handle any db error by dying

sub handle_error{
    my $error = shift;
    warn $error->{'msg'};
    die;
}

=head2 connect_to_object

standard connect to Net::DBus stuff

=cut

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
	    syslog(LOG_WARNING,"dbus connection error: $@ ... retry in few");
	    sleep 2;
	}else{
        #--- success
	    return $obj;
	}
    }
}

=head2 main

Connects to the Database, and Net::DBus, and connects the signals to the callbacks

=cut


sub main{

    $db = OESS::Database->new();
   
    openlog("OESS-Syslogger","ndelay,pid","local0");
    
    my $oess_config = "/etc/oess/database.xml";
    $oess = OESS::Database->new(config => $oess_config);

    my $dbus = OESS::DBus->new(service => 'org.nddi.openflow', instance => '/controller1');
    
	##dbus registers events to listen for on creation / scheduled  
	my $bus = Net::DBus->system;
    my $service = $bus->export_service("org.nddi.syslogger");
	my $object = OESS::Syslogger->new($service,$dbus->{'dbus'});
	if (!defined $object){
		#fuuu
		die("could not export org.nddi.syslogger service");		
	}
	
	
	if(defined($dbus)){
		$dbus->connect_to_signal("port_status",\&port_status);
		$dbus->connect_to_signal("datapath_join",\&datapath_join);
		$dbus->connect_to_signal("datapath_leave",\&datapath_leave);
	$dbus->start_reactor();
    }else{
	syslog(LOG_ERR,"Unable to connect to the DBus");
	die;
    }
}

=head1 OESS Syslogger

    OESS Syslogger sysloggs events about the active network, allowing for monitoring events to be generated in near
    real time.  Currently OESS syslogger logs to local0, and events that should be monitored are at level LOG_ERR

    Parameters: -f --foreground (runs the application in the foreground)
                -u --user (runs the application as a given user, as long as calling user has permission)

=cut

our($opt_f,$opt_u);
my $result = GetOptions("foreground" => \$opt_f,
			"user=s" => \$opt_u);

if($opt_f){
    main();
}else{
    my $daemon;
    if($opt_u){
        my $new_uid=getpwnam($opt_u);
        $daemon = Proc::Daemon->new( setuid => $new_uid,
                                     pid_file => '/var/run/oess/syslogger.pid'
            );
    }else{
        $daemon = Proc::Daemon->new(  pid_file => '/var/run/oess/syslogger.pid'
            );
    }
    my $kid = $daemon->Init;

    unless( $kid){
        if($opt_u){
            my $new_uid=getpwnam($opt_u);
	    my $new_gid=getgrnam($opt_u);
	    $EGID=$new_gid;
            $EUID=$new_uid;
        }
        main();
    }
}
