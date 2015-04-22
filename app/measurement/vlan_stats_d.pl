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
my $node_hash;
my $hosts;
my $dbus;

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

sub process_flow_stats{
    my $time = shift;
    my $dpid = shift;
    my $rules = shift;
    
    my $switch;
    #associate each rule with its in/out port/vlan
    foreach my $rule (@$rules){

	# might be some other rules or default forwarding or something, we can't match this to a 
	# vlan / port so skip
	next if (!defined $rule->{'match'});
	next if ($rule->{'match'}->{'dl_type'} eq '34997');
	if(!defined($switch->{$rule->{'match'}->{'in_port'}})){
	    $switch->{$rule->{'match'}->{'in_port'}} = {};
	}
	
	my $port = $switch->{$rule->{'match'}->{'in_port'}};
	if(!defined($port->{$rule->{'match'}->{'dl_vlan'}})){
	    $port->{$rule->{'match'}->{'dl_vlan'}} = {};
	}

	if(defined($rule->{'match'}->{'dl_dst'})){
	    if(!defined($port->{$rule->{'match'}->{'dl_vlan'}}->{'static_mac_addrs'})){
		$port->{$rule->{'match'}->{'dl_vlan'}}->{'static_mac_addrs'} = ();
	    }
	    push(@{$port->{$rule->{'match'}->{'dl_vlan'}}->{'static_mac_addrs'}},$rule);
	}

	$port->{$rule->{'match'}->{'dl_vlan'}}->{'in'} = $rule;

    }

    #for every port
    foreach my $port (keys (%{$switch})){
	#look at every vlan
	foreach my $vlan (keys (%{$switch->{$port}})){
	    
	    my $inbytes = $switch->{$port}->{$vlan}->{'in'}->{'byte_count'};
	    my $inpackets = $switch->{$port}->{$vlan}->{'in'}->{'packet_count'};
	    
	    
	    #do the RRD update
	    #RRD update!
	    update_rrd(dpid => $dpid, port => $port, vlan => $vlan, input => $inbytes, inUcast => $inpackets);
	    
	    foreach my $rule (@{$switch->{$port}->{$vlan}->{'mac_addrs'}}){
		my $static_in_bytes = $rule->{'in'}->{'byte_count'};
		my $static_in_packets = $rule->{'in'}->{'packet_count'};
		
		update_rrd(dpid => $dpid, port => $port, vlan => $vlan, mac_addr => $rule->{'match'}->{'dl_dst'}, input => $static_in_bytes, inUcast => $static_in_packets);
	    }
	}
    }
}

sub datapath_join_callback {
    my $dpid      = shift;
    my $ip_addr   = shift;
    my $port_list = shift;

    my $node = $oess->get_node_by_dpid( dpid => $dpid );
    
    my $query = "select * from host where host.external_id = ?";
    my $sth = $snapp_dbh->prepare($query);
    $sth->execute( $node->{'node_id'} );
    
    if(my $row = $sth->fetchrow_hashref()){
	$query = "update host set ip_address = ?, description = ?, dns_name = ?, community = ? where host_id = ?";
        $sth = $snapp_dbh->prepare($query)or handle_error($snapp_dbh,$DBI::errstr);
        $sth->execute($node->{'management_addr_ipv4'},$node->{'name'},$node->{'name'},"public",$row->{'host_id'})or handle_error($snapp_dbh,$DBI::errstr);
        my $host_id = $row->{'host_id'};

        #now update collection names if the host name changed
        $query = "update collection set name = replace(name,'" . $row->{'description'} . "','" . $node->{'name'} . "') where host_id = " . $row->{'host_id'};
        $sth = $snapp_dbh->prepare($query) or handle_error($snapp_dbh,$DBI::errstr);
        $sth->execute() or handle_error($snapp_dbh,$DBI::errstr);
        return $host_id;
    }else{
	my $query = "insert into host (ip_address,description,dns_name,community,external_id) VALUES (?,?,?,?,?)";
	my $sth = $snapp_dbh->prepare($query)or handle_error($snapp_dbh,$DBI::errstr);
	my $res = $sth->execute($node->{'management_addr_ipv4'},$node->{'name'},$node->{'name'},"community",$node->{'node_id'})or handle_error($snapp_dbh,$DBI::errstr);
	$res = $sth->{'mysql_insertid'};
	return $res;
    }

    _load_config();

}

sub datapath_leave_callback {
    my $dpid = shift;

    #do not do anything at this point...
}

sub update_rrd{
    my %params = @_;

    #find the node by dpid

    my $node = $node_hash->{$params{'dpid'}};
    #figure out the filename based on node, port, vlan
    #filename =  node_id/node_id-port-vlan.rrd
    
    if(!defined($node)){
	syslog(LOG_ERR,"Unable to find NODE DPID: " . $params{'dpid'});
	return;
    }

    my $file;
    if(!defined($params{'mac_addr'})){
	$file = $base_rrd_path . $node->{'node_id'} . "/" . $node->{'node_id'} . "-" . $params{'port'} . "-" . $params{'vlan'} . ".rrd";
    }else{
	$file = $base_rrd_path . $node->{'node_id'} . "/" . $node->{'node_id'} . "-" . $params{'port'} . "-" . $params{'vlan'} . "-" . $params{'mac_addr'} . ".rrd";
    }
    #if the file doesn't exist create it
    if(! -e $base_path . $file){
	my $res = create_rrd_file($file);
	if(!$res){
	    return;
	}
    }
    
    #here are our RRA's
    my $template = "input:inUcast";
    #generate our value String
    my $value = "N:" . $params{'input'} . ":" . $params{'inUcast'};

    my $tmp = $hosts->{$node->{'node_id'}};
    if(!defined($params{'mac_addr'})){
	if(defined($hosts->{$node->{'node_id'}}->{'collections'}->{$params{'port'} . "-" . $params{'vlan'}})){
	    #do nothing we already saw it
	}else{
	    #add the file to SNAPP (in case it was decommed, or never there)
	    add_snapp($file,$params{'dpid'},$params{'port'},$params{'vlan'});
	}
    }else{
	if(defined($hosts->{$node->{'node_id'}}->{'collections'}->{$params{'port'} . "-" . $params{'vlan'} . "-" . $params{'mac_addr'}})){
            #do nothing we already saw it
	}else{
            #add the file to SNAPP (in case it was decommed, or never there)
            add_snapp($file,$params{'dpid'},$params{'port'},$params{'vlan'},$params{'mac_addr'});
	}
    }
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

    #set the proper perms
    chmod 0755, $path;

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
    #push(@rrd_str,"DS:output:DERIVE:" . $coll_class->{'collection_interval'} * 3 . ":0:11811160064");
    push(@rrd_str,"DS:inUcast:DERIVE:" . $coll_class->{'collection_interval'} * 3 . ":0:11811160064");
    #push(@rrd_str,"DS:outUcast:DERIVE:" . $coll_class->{'collection_interval'} * 3 . ":0:11811160064");
    
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

    #set the proper file perms
    chmod 0644, $file;

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
    my $mac_addr = shift;
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
	#fire the datapath_join_callback... 
	#this should attempt to add the host to SNAPP
	#the next go around we should find the node and add collections
	datapath_join_callback($dpid,undef,undef);
	return;
    }

    $sth = $snapp_dbh->prepare("select * from collection where host_id = ? and premap_oid_suffix = ?") or handle_error($!);

    if(!defined($mac_addr)){
	$sth->execute($host->{'host_id'},$port . "-" . $vlan) or handle_error($!);
    }else{
	$sth->execute($host->{'host_id'},$port . "-" . $vlan . "-" . $mac_addr) or handle_error($!);
    }
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
	if(!defined($mac_addr)){
	    $sth->execute($node->{'name'} . "-" . $port . "-" . $vlan,$host->{'host_id'},$file,$port . "-" . $vlan,$port . "-" . $vlan,$collection_class->{'collection_class_id'},1) or handle_error($!);
	}else{
	    $sth->execute($node->{'name'} . "-" . $port . "-" . $vlan . "-" . $mac_addr,$host->{'host_id'},$file,$port . "-" . $vlan . "-" . $mac_addr,$port . "-" . $vlan . "-" . $mac_addr,$collection_class->{'collection_class_id'},1) or handle_error($!);
	}
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

	_load_config();
	return
    }
}


=head2 _load_config

    loads and caches our config
    we re-update when events like interface add / removes occur
    and when nodes connect and leave

=cut

sub _load_config{
    
    my $tmp = $oess->get_node_dpid_hash();

    #we need to reverse the hash...
    foreach my $key (keys (%{$tmp})){
	
	my $node = $oess->get_node_by_dpid( dpid => $tmp->{$key} );	
	next if($node->{'admin_state'} ne 'active');
	$node_hash->{$tmp->{$key}} = $node;
	
    }
    

    my $query = "select * from host";
    
    my $sth = $snapp_dbh->prepare($query);
    $sth->execute();

    while(my $host = $sth->fetchrow_hashref()){

    
	$query = "select * from collection natural join collection_instantiation where collection_instantiation.end_epoch = -1 and collection.host_id = ?";
	my $sth_collections = $snapp_dbh->prepare($query);
	$sth_collections->execute($host->{'host_id'});
	
	while(my $collection = $sth_collections->fetchrow_hashref()){
	    $host->{'collections'}->{$collection->{'premap_oid_suffix'}} = $collection;
	}

	$hosts->{$host->{'external_id'}} = $host;
	
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


=head2 get_flow_stats

=cut

sub get_flow_stats{

    if(-e '/var/run/oess/oess_is_overloaded.lock'){
        return;
    }

    warn "Fetching stats\n";
    my $nodes = $oess->get_current_nodes();
    foreach my $node (@$nodes){
	my $time;
        my $flows;
        eval {
            ($time,$flows) = $dbus->{'dbus'}->get_flow_stats($node->{'dpid'});
        };
        syslog(LOG_ERR, "error getting flow stats: $@") if $@;
        if (!$time || !$flows){
            return;
        }
	process_flow_stats($time,$node->{'dpid'},$flows);
    }

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

    _load_config();

    $dbus = OESS::DBus->new( service => "org.nddi.openflow",
			     instance => "/controller1", sleep_interval => .1, timeout => -1);
    if(defined($dbus)){
	$dbus->connect_to_signal("datapath_leave",\&datapath_leave_callback);
	$dbus->connect_to_signal("datapath_join",\&datapath_join_callback);
	$dbus->start_reactor( timeouts => [{interval => 30000, callback => Net::DBus::Callback->new(
						method => sub { get_flow_stats(); })},
					   {interval => 300000, callback => Net::DBus::Callback->new(
						method => sub { _load_config(); })}]);
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

our($opt_f,$opt_u, $opt_v);
my $result = GetOptions("foreground" => \$opt_f,
			"user=s" => \$opt_u,
                        "verbose" => \$opt_v);

if($opt_f){
    $SIG{HUP} = sub{ exit(0); };
    main();
}else{
    my $daemon;
    if($opt_v){
        $daemon = Proc::Daemon->new(  pid_file => '/var/run/oess/vlan_stats_d.pid',
                                      child_STDOUT => '/var/log/oess/vlan_stats.out',
                                      child_STDERR => '/var/log/oess/vlan_stats.log',
            );
    }else{
        $daemon = Proc::Daemon->new(  pid_file => '/var/run/oess/vlan_stats_d.pid');
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
    `chmod 0644 /var/run/oess/vlan_stats_d.pid`;
}
