#!/usr/bin/perl

use strict;
use English;
use Proc::Daemon;
use AnyEvent;
use OESS::Database;
use GRNOC::Log;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Client;
use GRNOC::RabbitMQ::Method;
use GRNOC::WebService::Client;
use Data::Dumper;
use JSON;
use strict;
use Getopt::Long;
use FindBin;
use XML::Simple;

use Log::Log4perl;

my $switch;
my $previous;
my $logger;
my $oess;
my $node_hash;
my $hosts;
my $rabbit_mq_client;
my $previous_data = {};
my $interval = 30;
my $tsds_ws;

use constant MAX_TSDS_MESSAGES => 100;


=head2 handle_error

this handles any errors we encounter with the databases, mostly we print he error message and die, but if we want to change
the behavior we only need to change it in once place

=cut

sub handle_error{
    my $error = shift;
    
    log_error("vlan_stats_d experienced an error: " . Dumper($error));
}

=head2 flow_stats_in_callback

    handle the flow_stats_in event, one thing to note is that this even is fired through nddi_rabbitmq nddi_rabbitmq handles all cases where
    there a multiple packets with this data.  flow_stats_in expects to have all the data returned in the rules variable

    expects a dpid, and an array of rules and their in_bytes/in_packets
    
    It associates each port/vlan with in and out rules.  So for multipoint vlans (ie.. > 2 endpoints) it will have an array for the output rules
    so that we can properly associate all data with every interface

=cut

sub process_flow_stats{
    my $time = shift;
    my $dpid = shift;
    my $rules = shift;
    
    $logger->debug("Calling process_flow_stats at $time");

    my $switch;
    #associate each rule with its in/out port/vlan
    foreach my $rule (@$rules){

	# might be some other rules or default forwarding or something, we can't match this to a 
	# vlan / port so skip
	next if (!defined $rule->{'match'});
	next if (!defined $rule->{'match'}->{'in_port'});
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

    my @tsds_work_queue = ();

    #for every port
    foreach my $port (keys (%{$switch})){
	#look at every vlan
	foreach my $vlan (keys (%{$switch->{$port}})){
	    
	    my $inbytes = $switch->{$port}->{$vlan}->{'in'}->{'byte_count'};
	    my $inpackets = $switch->{$port}->{$vlan}->{'in'}->{'packet_count'};
	    
            if(!defined($previous_data->{$dpid})){
                $previous_data->{$dpid} = { };
            }

            if(!defined($previous_data->{$dpid}->{$port})){
                $previous_data->{$dpid}->{$port} = {};
            }

            if(!defined($previous_data->{$dpid}->{$port}->{$vlan})){
                $previous_data->{$dpid}->{$port}->{$vlan} = {time => $time,
							     in_bytes => $inbytes,
							     in_packets => $inpackets};
                next;
            }

            my $previous = $previous_data->{$dpid}->{$port}->{$vlan};

	    # If the flow stats poll interval is zero, then we just
	    # ignore this update.
	    if ($time == $previous->{'time'}) {
		$logger->warn("Calculated poll interval was zero. Ignoring this update.");
		next;
	    }

            my $bps = (($inbytes - $previous->{'in_bytes'}) * 8) / ($time - $previous->{'time'});
            my $pps = $inpackets - $previous->{'in_packets'} / ($time - $previous->{'time'});

            push(@tsds_work_queue, {
		interval=> $interval,
		meta => {
		    dpid => $dpid,
		    port => $port,
		    vlan => $vlan
		},
		time => $time,
		type => "oess_of_stats",
		values => {
		    bps => $bps,
		    pps => $pps
		}
	    });

            $previous->{'in_bytes'} = $inbytes;
            $previous->{'in_packets'} = $inpackets;
            $previous->{'time'} = $time;

	    foreach my $rule (@{$switch->{$port}->{$vlan}->{'mac_addrs'}}){
		my $static_in_bytes = $rule->{'in'}->{'byte_count'};
		my $static_in_packets = $rule->{'in'}->{'packet_count'};
                
                if(!defined($previous->{'mac_addrs'})){
                    $previous->{'mac_addrs'} = {};
                }

                if(!defined($previous->{'mac_addrs'}->{$rule->{'match'}->{'dl_dst'}})){
                    $previous->{'mac_addrs'}->{$rule->{'match'}->{'dl_dst'}} = {time => $time,
                                                                                in_bytes => $static_in_bytes,
                                                                                in_packets => $static_in_packets};
                    next;
                }
                
                my $prev_static = $previous->{'mac_addrs'}->{$rule->{'match'}->{'dl_dst'}};

                my $bps = (($inbytes - $prev_static->{'in_bytes'}) * 8) / ($time - $prev_static->{'time'});
                my $pps = $inpackets - $prev_static->{'in_packets'} / ($time - $prev_static->{'time'});

                push(@tsds_work_queue, {
		    interval=> $interval,
		    meta => {
			port => $port,
			dpid => $dpid,
			vlan => $vlan,
			mac_addrs => $rule->{'match'}->{'dl_dst'}
		    },
		    time => $time,
		    type => "oess_of_stats",
		    values => {
			bps => $bps,
			pps => $pps
		    }
		});

                $prev_static->{'in_bytes'} = $inbytes;
                $prev_static->{'in_packets'} = $inpackets;
                $prev_static->{'time'} = $time;
	    }
	}
    }

    send_to_tsds(\@tsds_work_queue);
}

sub send_to_tsds{
    my $work_queue = shift;

    while(scalar(@$work_queue) > 0 ){
        my @msgs = splice(@$work_queue, 0, MAX_TSDS_MESSAGES);

        my $res = $tsds_ws->add_data( data => encode_json(\@msgs));
	if (!defined $res) {
	    $logger->error("Could not add data to tsds.");
	}
    }
}

sub datapath_join_callback {
    my $dpid      = shift;
    my $ip_addr   = shift;
    my $port_list = shift;

    _load_config();

}

sub datapath_leave_callback {
    my $dpid = shift;

    #do not do anything at this point...
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
}

sub _connect_to_tsds {
    my $path   = shift;
    my $config = XML::Simple::XMLin($path);

    my $client = GRNOC::WebService::Client->new(
	url    => $config->{'tsds'}->{'url'} . "/push.cgi",
	uid    => $config->{'tsds'}->{'username'},
	passwd => $config->{'tsds'}->{'password'}
    );

    return $client;
}

=head2 get_flow_stats

=cut

sub get_flow_stats{
    my $self = shift;

    $logger->debug("Calling get_flow_stats");

    if(-e '/var/run/oess/oess_is_overloaded.lock'){
        return;
    }

    my $nodes = $oess->get_current_nodes();
    foreach my $node (@$nodes){
	my $time;
        my $flows;
	my $results;
        eval {
            $results = $rabbit_mq_client->get_flow_stats(
		dpid => int($node->{'dpid'}),
		async_callback => sub {
		    my $results = shift;

		    $time = $results->{'results'}->[0]->{'timestamp'};
		    $flows = $results->{'results'}->[0]->{'flow_stats'};
		    if (!$time || !$flows){
			$logger->error("Couldn't get flow stats for node " . $node->{'dpid'});
			return;
		    }

		    process_flow_stats($time, $node->{'dpid'}, $flows);
		}
	    );
        };
        $logger->error("error getting flow stats: $@") if $@;
    }
}

=head2 main

    Basically connects to SNAPP DB, OESS-DB, and Net::DBus and connects the flow_stats_in callback to the 
    flow_stats_in event

=cut

sub main{

    Log::Log4perl::init('/etc/oess/logging.conf');
    $logger = Log::Log4perl->get_logger('OESS.Measurement');

    $logger->info("Starting vlan_stats_d");

    my $oess_config = "/etc/oess/database.xml";
    $oess = OESS::Database->new(config => $oess_config);
    if (!defined $oess) {
	$logger->error( "Unable to connect to OESS database");
	die;
    }


    $tsds_ws = _connect_to_tsds($oess_config);
    if (!defined $tsds_ws) {
	$logger->error("Couldn't connect to TSDS at $tsds_ws.");
	die;
    }

    _load_config();

    $rabbit_mq_client = GRNOC::RabbitMQ::Client->new( host => $oess->{'rabbitMQ'}->{'host'},
						      port => $oess->{'rabbitMQ'}->{'port'},
						      user => $oess->{'rabbitMQ'}->{'user'},
						      pass => $oess->{'rabbitMQ'}->{'pass'},
						      exchange => 'OESS',
						      topic => 'OF.NOX.RPC',
						      timeout => 100);

    my $rabbit_dispatcher = GRNOC::RabbitMQ::Dispatcher->new( host => $oess->{'rabbitMQ'}->{'host'},
							      port => $oess->{'rabbitMQ'}->{'port'},
							      user => $oess->{'rabbitMQ'}->{'user'},
							      pass => $oess->{'rabbitMQ'}->{'pass'},
                                                              exchange => 'OESS',
							      topic => 'OF.NOX.event');

    my $method = GRNOC::RabbitMQ::Method->new( name        => 'datapath_join',
                                               topic       => "OF.NOX.event",
					       callback    => sub { datapatch_join_callback(@_) },
					       description => "Datapath Join callback when a device joins");

    $method->add_input_parameter( name => "dpid",
                                  description => "The DPID of the switch which joined",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NUMBER_ID);

    $method->add_input_parameter( name => "ip",
                                  description => "The IP of the swich which has joined",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NUMBER_ID);

    $method->add_input_parameter( name => "ports",
                                  description => "A list of ports that exist on the node, and their details",
                                  required => 1,
                                  schema => { 'type'  => 'array',
                                              'items' => [ 'type' => 'object',
                                                           'properties' => { 'hw_addr'    => {'type' => 'number'},
                                                                             'curr'       => {'type' => 'number'},
                                                                             'name'       => {'type' => 'string'},
                                                                             'speed'      => {'type' => 'number'},
                                                                             'supported'  => {'type' => 'number'},
                                                                             'enabled'    => {'type' => 'number'}, # bool
                                                                             'flood'      => {'type' => 'number'}, # bool
                                                                             'state'      => {'type' => 'number'},
                                                                             'link'       => {'type' => 'number'}, # bool
                                                                             'advertised' => {'type' => 'number'},
                                                                             'peer'       => {'type' => 'number'},
                                                                             'config'     => {'type' => 'number'},
                                                                             'port_no'    => {'type' => 'number'}
                                                                           }
                                                         ]
                                            } );
    $rabbit_dispatcher->register_method($method);
    $logger->info("Rabbit setup vlan_stats_d");

    my $collector_interval = AnyEvent->timer( after => $interval,
					      interval => $interval,
					      cb => sub{ get_flow_stats();});
    
    my $config_reload_interval = AnyEvent->timer( after => $interval * 10,
						  interval => $interval * 10,
						  cb => sub{ _load_config(); });

    $rabbit_dispatcher->start_consuming();
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
