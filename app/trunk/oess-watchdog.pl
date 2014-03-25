#!/usr/bin/perl

use strict;
use warnings;
use Log::Log4perl;
use XML::Simple;
use Proc::Daemon;
use English;
use Getopt::Long;
use Data::Dumper;
use Proc::ProcessTable;
use Switch;

use constant OESS_OVERLOADED => 1;
use constant OESS_LOAD_OK => 0;
use constant OESS_LOAD_UNKNOWN => 2;
use constant WATCHDOG_FILE => '/var/run/oess_is_overloaded.lock';


my $complete = 0;
my $interval = 10;

my $fvd_status = {};
my $vlan_stats_status = {};
my $nox_status = {};

$fvd_status->{'history'} = ();
$vlan_stats_status->{'history'} = ();
$nox_status->{'history'} = ();

my $log;
my $config;
my $proc_table;

sub process_config{
    my $config_file = shift;
    $config = XML::Simple::XMLin($config_file);
    
    $interval = $config->{'monitoring'}->{'interval'};

    $fvd_status->{'over_time'} = $config->{'monitoring'}->{'fvd'}->{'over_seconds'};
    $fvd_status->{'over_value'} = $config->{'monitoring'}->{'fvd'}->{'over_value'};
    $fvd_status->{'under_time'} = $config->{'monitoring'}->{'fvd'}->{'under_seconds'};
    $fvd_status->{'under_value'} = $config->{'monitoring'}->{'fvd'}->{'under_value'};
    $fvd_status->{'status'} = OESS_LOAD_UNKNOWN;

    $nox_status->{'over_time'} = $config->{'monitoring'}->{'nox'}->{'over_seconds'};
    $nox_status->{'over_value'} = $config->{'monitoring'}->{'nox'}->{'over_value'};
    $nox_status->{'under_time'} = $config->{'monitoring'}->{'nox'}->{'under_seconds'};
    $nox_status->{'under_value'} = $config->{'monitoring'}->{'nox'}->{'under_value'};
    $nox_status->{'status'} = OESS_LOAD_UNKNOWN;

    $vlan_stats_status->{'over_time'} = $config->{'monitoring'}->{'vlan_stats'}->{'over_seconds'};
    $vlan_stats_status->{'over_value'} = $config->{'monitoring'}->{'vlan_stats'}->{'over_value'};
    $vlan_stats_status->{'under_time'} = $config->{'monitoring'}->{'vlan_stats'}->{'under_seconds'};
    $vlan_stats_status->{'under_value'} = $config->{'monitoring'}->{'vlan_stats'}->{'under_value'};
    $vlan_stats_status->{'status'} = OESS_LOAD_UNKNOWN;
}

sub core{
    Log::Log4perl::init_and_watch('/etc/oess/logging.conf',10);
    $log = Log::Log4perl->get_logger("OESS-WATCHDOG");
    process_config("/etc/oess/watchdog.conf");

    $proc_table = new Proc::ProcessTable;

    while($complete == 0){
        
        $log->debug("Running watchdog");

        #associate a process to a pid
        get_processes();
        
        #do some work
        monitor_vlan_stats();
        monitor_fvd();
        monitor_nox();

        #check the resulting status
        if($fvd_status->{'status'} == OESS_OVERLOADED){
            if(-e WATCHDOG_FILE){
                $log->debug("system is already signaled overloaded");
            }else{
                $log->warn("Forwarding Verification determined to be overloaded!");
                my $cmd = 'touch ' . WATCHDOG_FILE;
                `$cmd`;
            }
        }

        #check the resulting status
        if($vlan_stats_status->{'status'} == OESS_OVERLOADED){
            if(-e WATCHDOG_FILE){
                $log->debug("system is already signaled overloaded");
            }else{
                $log->warn("VLAN Stats determined to be overloaded!");
                my $cmd = 'touch ' . WATCHDOG_FILE;
                `$cmd`;
            }
        }

        #check the resulting status
        if($nox_status->{'status'} == OESS_OVERLOADED){
            if(-e WATCHDOG_FILE){
                $log->debug("system is already signaled overloaded");
            }else{
                $log->warn("NOX determined to be overloaded!");
                my $cmd = 'touch ' . WATCHDOG_FILE;
                `$cmd`;
            }
        }
        
        #check for recovery
        if($vlan_stats_status->{'status'} != OESS_OVERLOADED &&
           $fvd_status->{'status'} != OESS_OVERLOADED &&
           $nox_status->{'status'} != OESS_OVERLOADED){
            if(-e '/var/run/oess_is_overloaded.lock'){
                #we are recovered remove this file
                my $cmd = 'rm ' . WATCHDOG_FILE;
                `$cmd`;
            }
        }

        #sleep for our interval
        sleep($interval);
    }

}

sub get_processes{

    my $table = $proc_table->table;
    $fvd_status->{'process'} = undef;
    $vlan_stats_status->{'process'} = undef;
    $nox_status->{'process'} = undef;
    foreach my $process (@$table){

        $log->debug("Process: " . Data::Dumper::Dumper($process));

        switch($process->{'fname'}){
            case 'oess-fvd.pl'{
                $fvd_status->{'process'} = $process;
            }
            case 'vlan_stats_d.pl'{
                $vlan_stats_status->{'process'} = $process;
            }
            case 'nox_core'{
                $nox_status->{'process'} = $process;
            }else{
                next;
            }
        }
    }

    if(!defined($vlan_stats_status->{'process'})){
        $log->error("Unable to find a process called 'vlan_stats_d.pl'");
    }

    if(!defined($nox_status->{'process'})){
        $log->error("Unable to find a process called 'nox_cored'");
    }

    if(!defined($fvd_status->{'process'})){
        $log->error("Unable to find a process called 'oess-fvd.pl'");
    }

}

sub monitor_fvd{
    
    if(!defined($fvd_status->{'process'})){
        $fvd_status->{'status'} = OESS_LOAD_UNKNOWN;
        return;
    }

    if($#{$fvd_status->{'history'}} >= 1000){
        my $tmp = shift @{$fvd_status->{'history'}};
    }
    
    my $usage = calc_usage($fvd_status->{'process'});

    $log->debug("FVD running at: " . $usage ." util");
    push(@{$fvd_status->{'history'}},$usage);

    if($fvd_status->{'status'} == OESS_OVERLOADED){

        if(is_under($fvd_status->{'history'},$fvd_status->{'under_time'}, $fvd_status->{'under_value'})){
            $log->warn("Forwarding Verification is no longer considered overloaded... setting to recovered");
            $fvd_status->{'status'} = OESS_LOAD_OK;
        }else{
            $log->debug("Forwarding verification is still overloaded");
        }

    }else{
        
        if(is_over($fvd_status->{'history'},$fvd_status->{'over_time'},$fvd_status->{'over_value'})){
            $log->warn("Forwarding Verification has exceeded threshold, and is considered overloaded");
            $fvd_status->{'status'} = OESS_OVERLOADED;
        }else{
            $log->debug("Forwarding verification operating as expected");
        }
    }
}

sub monitor_vlan_stats{

    if(!defined($vlan_stats_status->{'process'})){
        $vlan_stats_status->{'status'} = OESS_LOAD_UNKNOWN;
        return;
    }

    if($#{$vlan_stats_status->{'history'}} >= 1000){
        shift @{$vlan_stats_status->{'history'}};
    }

    my $usage = calc_usage($vlan_stats_status->{'process'});

    $log->debug("VLAN Stats running at: " . $usage ." util");
    push(@{$vlan_stats_status->{'history'}},$usage);

    if($vlan_stats_status->{'status'} == OESS_OVERLOADED){

        if(is_under($vlan_stats_status->{'history'},$vlan_stats_status->{'under_time'}, $vlan_stats_status->{'under_value'})){
            $log->warn("VLAN Stats is no longer considered overloaded... setting to recovered");
            $vlan_stats_status->{'status'} = OESS_LOAD_OK;
        }else{
            $log->debug("VLAN Stats is still overloaded");
        }

    }else{

        if(is_over($vlan_stats_status->{'history'},$vlan_stats_status->{'over_time'},$vlan_stats_status->{'over_value'})){
            $log->warn("VLAN stats has exceeded threshold, and is considered overloaded");
            $vlan_stats_status->{'status'} = OESS_OVERLOADED;
        }else{
            $log->debug("VLAN Stats operating as expected");
        }
    }
}

sub monitor_nox{

    if(!defined($nox_status->{'process'})){
        $nox_status->{'status'} = OESS_LOAD_UNKNOWN;
        return;
    }

    if($#{$nox_status->{'history'}} >= 1000){
        shift @{$nox_status->{'history'}};
    }

    my $usage =calc_usage($nox_status->{'process'});

    $log->debug("NOX running at: " . $usage ." util");
    push(@{$nox_status->{'history'}},$usage);

    if($nox_status->{'status'} == OESS_OVERLOADED){

        if(is_under($nox_status->{'history'},$nox_status->{'under_time'}, $nox_status->{'under_value'})){
            $log->warn("NOX is no longer considered overloaded... setting to recovered");
            $nox_status->{'status'} = OESS_LOAD_OK;
        }else{
            $log->debug("NOX is still overloaded");
        }

    }else{

        if(is_over($nox_status->{'history'},$nox_status->{'over_time'},$nox_status->{'over_value'})){
            $log->warn("NOX has exceeded threshold, and is considered overloaded");
            $nox_status->{'status'} = OESS_OVERLOADED;
        }else{
            $log->debug("NOX operating as expected");
        }
    }
}


sub is_over{
    my $history = shift;
    my $over_time = shift;
    my $over_value = shift;

    my $total_samples = $over_time / $interval;
    $log->debug("total samples: " . $total_samples);

    if($#{$history} < $total_samples){
        return 0;
    }
    for(my $i= 0;$i<$total_samples;$i++){
        if($history->[$#{$history} - $i] <=  $over_value){
            return 0;
        }

    }
    return 1;
    
}

sub is_under{
    my $history = shift;
    my $under_time = shift;
    my $under_value = shift;

    my $total_samples = $under_time / $interval;

    if($#{$history} < $total_samples){
        return 0;
    }

    for(my $i=0;$i<$total_samples;$i++){
        
        if($history->[$#{$history} - $i] >= $under_value){
            return 0
        }

    }

    return 1;

}

sub calc_usage{
    my $process = shift;

    my $cmd = "top -b -n 1 -p" . $process->{'pid'};
    my $res = `$cmd`;
    my @lines = split(/\n/,$res);

    foreach my $line (@lines){
        if($line =~ /$process->{'pid'} /){
            $line =~ /\d+\s+\w+\s+\d+\s+\d+\s+\S+\s+\S+\s+\S+\s+\w\s+(\S+)/;
            return $1;
        }
    }
    

    return 0;
    
}

sub main{
    my $is_daemon = 0;
    my $verbose;
    my $username;
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
                pid_file => '/var/run/oess/oess-watchdog.pid',
                child_STDOUT => '/var/log/oess/oess-watchdog.out',
                child_STDERR => '/var/log/oess/oess-watchdog.log',
                );
        } else {
            $daemon = Proc::Daemon->new(
                pid_file => '/var/run/oess/oess-watchdog.pid'
                );
        }
        my $kid_pid = $daemon->Init;

        if ($kid_pid) {
            return;
        }

        core();
    }
    #not a deamon, just run the core;
    else {
        $SIG{HUP} = sub{ exit(0); };
        core();
    }
    
}

main();
