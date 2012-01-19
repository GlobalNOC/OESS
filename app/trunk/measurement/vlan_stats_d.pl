#!/usr/bin/perl

use strict;
use English;
use Proc::Daemon;
use OESS::Database;
use OESS::DBus;
use Data::Dumper;
use strict;
use Getopt::Long;
use Sys::Syslog qw(:standard :macros);
use FindBin;
use RRDs;


my $switch;
my $previous;
my $base_rrd_path = "per_flow/";
my $snapp_dbh;
my $oess;
my $base_path;
my $collection_class_name;
=head2 handle_error

this handles any errors we encounter with the databases, mostly we print he error message and die, but if we want to change
the behavior we only need to change it in once place

=cut

sub handle_error{
    my $error = shift;
    syslog(LOG_ERR,"vlan_stats_d experienced an error: " . Dumper($error));
}

=head2 flow_stats_in_callback

    handle the flow_stats_in event, one thing to note is that this even is fired through nddi_dbus nddi_dbus handles all cases where
    there a multiple packets with this data.  flow_stats_in expects to have all the data returned in the rules variable

    expects a dpid, and an array of rules and their in_bytes/in_packets
    
    It associates each port/vlan with in and out rules.  So for multipoint vlans (ie.. > 2 endpoints) it will have an array for the output rules
    so that we can properly associate all data with every interface

=cut

sub flow_stats_in_callback{
    my $dpid = shift;
    my $rules = shift;
    
    my $switch;

    #associate each rule with its in/out port/vlan
    foreach my $rule (@$rules){

	if(!defined($switch->{$rule->{'match'}->{'in_port'}})){
	    $switch->{$rule->{'match'}->{'in_port'}} = {};
	}
	
	my $port = $switch->{$rule->{'match'}->{'in_port'}};
	if(!defined($port->{$rule->{'match'}->{'dl_vlan'}})){
	    $port->{$rule->{'match'}->{'dl_vlan'}} = {};
	}

	$port->{$rule->{'match'}->{'dl_vlan'}}->{'in'} = $rule;

	my $vlan = $rule->{'match'}->{'dl_vlan'};

	foreach my $action (@{$rule->{'actions'}}){
	    
	    if(defined($action->{'port'})){
		if(!defined($switch->{$action->{'port'}})){
		    $switch->{$action->{'port'}} = {};
		}
		if(!defined($switch->{$action->{'port'}}->{$vlan}->{'out'})){
		    $switch->{$action->{'port'}}->{$vlan}->{'out'} = ();
		}
		push(@{$switch->{$action->{'port'}}->{$vlan}->{'out'}},$rule);
	    }

	    if(defined($action->{'vlan_vid'})){
		$vlan = $action->{'vlan_vid'};
	    }
	}
    }

    #for every port
    foreach my $port (keys (%{$switch})){
	#look at every vlan
	foreach my $vlan (keys (%{$switch->{$port}})){
	    
	    my $inbytes = $switch->{$port}->{$vlan}->{'in'}->{'byte_count'};
	    my $inpackets = $switch->{$port}->{$vlan}->{'in'}->{'packet_count'};
	    
	    my $outbytes = 0;
	    my $outpackets = 0;
	    
	    #the output is the aggregate of all the rules with actions matching our port/vlan
	    foreach my $out (@{$switch->{$port}->{$vlan}->{'out'}}){
		#need to compare to previous counts
		
		$outbytes += $out->{'byte_count'};
		$outpackets += $out->{'packet_count'};
	    }

	    #do the RRD update
	    #RRD update!
	    update_rrd(dpid => $dpid, port => $port, vlan => $vlan, input => $inbytes, output => $outbytes, inUcast => $inpackets, outUcast => $outpackets);
	}
    }
}

sub datapath_join_callback {
    my $dpid      = shift;
    my $ip_addr   = shift;
    my $port_list = shift;

    run_snapp_config_gen();
}

sub datapath_leave_callback {
    my $dpid = shift;

    run_snapp_config_gen();
}

# this should probably be a library call, should consider refactoring this instead of system calls
sub run_snapp_config_gen{

    my $result = system("$FindBin::Bin/snapp-config-gen");

    if ($result){
	syslog(LOG_ERR, "Error running snapp-config-gen: " . $!);
    }
}

sub update_rrd{
    my %params = @_;
    
    #find the node by dpid
    my $node = $oess->get_node_by_dpid( dpid => $params{'dpid'});
    #figure out the filename based on node, port, vlan
    #filename =  node_id/node_id-port-vlan.rrd
    if(!defined($node)){
	return;
    }
    my $file = $base_rrd_path . $node->{'node_id'} . "/" . $node->{'node_id'} . "-" . $params{'port'} . "-" . $params{'vlan'} . ".rrd";

    #if the file doesn't exist create it
    if(! -e $base_path . $file){
	my $res = create_rrd_file($file);
	if(!$res){
	    return;
	}
    }
    
    #here are our RRA's
    my $template = "input:output:inUcast:outUcast";
    #generate our value String
    my $value = "N:" . $params{'input'} . ":" . $params{'output'} . ":" . $params{'inUcast'} . ":" . $params{'outUcast'};

    #add the file to SNAPP (in case it was decommed, or never there)
    add_snapp($file,$params{'dpid'},$params{'port'},$params{'vlan'});
    
    #do the update and log any error
    RRDs::update($base_path . $file,"--template",$template,$value);
    my $error = RRDs::error();
    if(defined($error)){
	syslog(LOG_ERR,"There was an error updating RRD file $file: " . $error);
    }
}


=head2 create_rrd_file

creates an rrdifle based on the name (path is currently hard coded)

=cut

sub create_rrd_file{
    my $file = shift;
    $file = $base_path . $file;

    my $path = $file;
    $path =~ /(.*)\/.*\.rrd/;
    $path = $1;

    #make the path if it doesn't exist
    `mkdir -p $path`;

    my $sth = $snapp_dbh->prepare("select * from collection_class where collection_class.name = ?") or handle_error();
    if(!defined($sth)){
	return 0;
    }
    
    $sth->execute($collection_class_name) or handle_error();
    
    my $coll_class = $sth->fetchrow_hashref();
    if(!defined($coll_class)){
	return 0;
    }

    $sth = $snapp_dbh->prepare("select * from rra where rra.collection_class_id = ?") or handle_error();
    if(!defined($sth)){
	return 0;
    }

    $sth->execute($coll_class->{'collection_class_id'});
    
    my @rras;
    while(my $rra = $sth->fetchrow_hashref()){
	push(@rras,$rra);
    }

    my @rrd_str;
    push(@rrd_str,"-s " . $coll_class->{'collection_interval'});
    push(@rrd_str,"DS:input:DERIVE:" . $coll_class->{'collection_interval'} * 3 . ":0:11811160064");
    push(@rrd_str,"DS:output:DERIVE:" . $coll_class->{'collection_interval'} * 3 . ":0:11811160064");
    push(@rrd_str,"DS:inUcast:DERIVE:" . $coll_class->{'collection_interval'} * 3 . ":0:11811160064");
    push(@rrd_str,"DS:outUcast:DERIVE:" . $coll_class->{'collection_interval'} * 3 . ":0:11811160064");
    
    foreach my $rra (@rras){
	my $rows = ($rra->{'num_days'} * 60 * 60 * 24) / $coll_class->{'collection_interval'} / $rra->{'step'};
	push(@rrd_str,"RRA:" . $rra->{'cf'} . ":" . $rra->{'xff'} . ":" . $rra->{'step'} . ":" . $rows);
    }

    #create RRD file, and log any error
    RRDs::create($file,@rrd_str);
    my $error = RRDs::error();
    if(defined($error)){
	syslog(LOG_ERR,"Error trying to create rrdfile: " . $file . "\n$error");
	return 0;
    }

    return 1;
}

=head2 add_snapp

Adds the data into the SNAPP database, (note the collector_id = 1 to let SNAPP collector know to ignore this)

if the collection is already in SNAPP then we just verify it is active, if it isn't we activate it

=cut

sub add_snapp{
    my $file = shift;
    my $dpid = shift;
    my $port = shift;
    my $vlan = shift;

    my $node = $oess->get_node_by_dpid( dpid => $dpid);
    my $host;
    
    if(!defined($node)){
	return;
    }
    my $sth = $snapp_dbh->prepare("select * from host where external_id = ?") or handle_error($!);
    if(!defined($sth)){
	next;
    }
    $sth->execute($node->{'node_id'}) or handle_error($!);
    if(my $row = $sth->fetchrow_hashref()){
	$host = $row;
    }else{
	syslog(LOG_ERR,"Unable to find node (" . $node->{'node_id'} . ") in SNAPP");
	return;
    }

    $sth = $snapp_dbh->prepare("select * from collection where host_id = ? and premap_oid_suffix = ?") or handle_error($!);
    $sth->execute($host->{'host_id'},$port . "-" . $vlan) or handle_error($!);
    if(my $row = $sth->fetchrow_hashref()){
	#hey this collection already exists
	$sth = $snapp_dbh->prepare("select * from collection_instantiation where collection_id = ? and end_epoch = -1") or handle_error($!);
	if(!defined($sth)){
	    return;
	}
	$sth->execute($row->{'collection_id'}) or handle_error($!);
	if(my $instance = $sth->fetchrow_hashref()){
	    #already an active instance do nothing
	    return;
	}else{
	    #there is not an active instance create it
	    $sth = $snapp_dbh->prepare("insert into collection_instantiation (collection_id,end_epoch,start_epoch,threshold,description) VALUES (?,-1,UNIX_TIMESTAMP(NOW()),0,'')") or handle_error($!);
	    if(!defined($sth)){
		return;
	    }
	    $sth->execute($row->{'collection_id'}) or handle_error($!);
	    return;
	}
    }else{
	#no collection found create it and the instance
	$sth = $snapp_dbh->prepare("select * from collection_class where collection_class.name = ?") or handle_error($!);
	if(!defined($sth)){
	    return;
	}
	$sth->execute($collection_class_name) or handle_error($!);
	
	my $collection_class = $sth->fetchrow_hashref();
	if(!defined($collection_class)){
	    return;
	}
	
	

	
	$sth = $snapp_dbh->prepare("insert into collection (name,host_id,rrdfile,premap_oid_suffix,long_identifier,collection_class_id,oid_suffix_mapping_id,collector_id) VALUES (?,?,?,?,?,?,?,1)") or handle_error($!);
	if(!defined($sth)){
	    return;
	}
	$sth->execute($node->{'name'} . "-" . $port . "-" . $vlan,$host->{'host_id'},$file,$port . "-" . $vlan,$port . "-" . $vlan,$collection_class->{'collection_class_id'},1) or handle_error($!);
	my $collection_id = $sth->{'mysql_insertid'};
	if(!defined($collection_id)){
	    syslog(LOG_ERR,"Unable to add collection: $!");
	    return;
	}
	$sth = $snapp_dbh->prepare("insert into collection_instantiation (collection_id,end_epoch,start_epoch,threshold,description) VALUES (?,-1,NOW(),0,'')") or handle_error($!);
	if(!defined($sth)){
	    return;
	}
	$sth->execute($collection_id) or handle_error($!);
	return
    }
}

=head2 connect_to_object

standard connect to Net::DBus

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

=head2 connect_to_snapp

    Connect to the SNAPP Database 
    Takes 1 param the snapp config file

=cut

sub connect_to_snapp{
    my $snapp_config = shift;
    my $config = XML::Simple::XMLin($snapp_config);
    my $username = $config->{'db'}->{'username'};
    my $password = $config->{'db'}->{'password'};
    my $database = $config->{'db'}->{'name'};
    my $snapp_db = DBI->connect("DBI:mysql:$database", $username, $password);
    $collection_class_name = $config->{'db'}->{'collection_class_name'};
    return $snapp_db;
}


=head2 main

    Basically connects to syslog, SNAPP DB, OESS-DB, and Net::DBus and connects the flow_stats_in callback to the 
    flow_stats_in event

=cut

sub main{
    openlog("OESS-vlan_stats_d","ndelay,pid","local0");
    syslog(LOG_NOTICE, "Starting vlan_stats_d");

    my $oess_config = "/etc/oess/database.xml";
    $oess = OESS::Database->new(config => $oess_config);

    if (! defined $oess){
	syslog(LOG_ERR, "Unable to connect to OESS database");
	die;
    }

    $snapp_dbh = connect_to_snapp($oess->get_snapp_config_location());

    if (! defined $snapp_dbh){
	syslog(LOG_ERR, "Unable to connect to snapp database.");
	die;
    }
    
    my $sth = $snapp_dbh->prepare("select value from global where name = 'rrddir'");
    $sth->execute();
    $base_path = $sth->fetchrow_hashref()->{'value'};
    if(!defined($base_path)){
	syslog(LOG_ERR, "Unable to find base RRD directory from snapp database.");
	die;
    }
    my $dbus = OESS::DBus->new( service => "org.nddi.openflow",
	                        instance => "/controller1", sleep_interval => .1, timeout => -1);
    if(defined($dbus)){
	$dbus->connect_to_signal("flow_stats_in",\&flow_stats_in_callback);
	$dbus->connect_to_signal("datapath_leave",\&datapath_leave_callback);
	$dbus->connect_to_signal("datapath_join",\&datapath_join_callback);
	$dbus->start_reactor();
    }else{
	syslog(LOG_ERR,"Unable to connect to dbus");
	die;
    }
}


=head1 OESS vlan_stats_d

vlan_stats_d collects per-interface per-vlan statistics through OESS

Parmeters: -f --foreground runs the application in the foreground (ie... no fork)
           -u --user runs the application as the given user (presuming the calling user has permission to do so)

=cut

our($opt_f,$opt_u);
my $result = GetOptions("foreground" => \$opt_f,
			"user=s" => \$opt_u);

if($opt_f){
    main();
}else{

    my $daemon = Proc::Daemon->new(  pid_file => '/var/run/oess/vlan_stats_d.pid');

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
