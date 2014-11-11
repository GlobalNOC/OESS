use strict;
use warnings;

package OESS::Watchdog;

#------ NDDI OESS Database Interaction Module
##-----
##----- $HeadURL: svn+ssh://svn.grnoc.iu.edu/grnoc/oe-ss/perl-lib/OESS-Database/trunk/lib/OESS/Database.pm $
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----
##----- Watches the OESS process for anything getting out of control
##----- and raises the overloaded flag
##-------------------------------------------------------------------------
##
## Copyright 2011 Trustees of Indiana University
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

=head1 NAME

OESS::Watchdog - Process watching daemone

=head1 SYNOPSIS

This module watches other OESS process and verifies that they are not
using all of the available resources

Some examples:

    use OESS::Watchdog;

    my $wd = new OESS::Watchdog();

    while(1){
      $wd->do_work();
      sleep($wd->{'interval'});
    }

=cut

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
use constant WATCHDOG_FILE => '/var/run/oess/oess_is_overloaded.lock';

=head2 new

=cut

sub new{
    my $that = shift;
    my $class = ref($that) || $that;

    my $log = Log::Log4perl->get_logger("OESS.Watchdog");

    my %args = (
        interval => 1000,
        timeout  => 15000,
        @_
        );

    my $self = \%args;

    bless $self, $class;
    $self->{'logger'}    = $log;
    
    $self->_process_config("/etc/oess/watchdog.conf");

    $self->{'proc_table'} = new Proc::ProcessTable;

    return $self;
}



sub _process_config{
    my $self = shift;
    my $config_file = shift;
    my $config = XML::Simple::XMLin($config_file);

    $self->{'interval'} = $config->{'monitoring'}->{'interval'};

    $self->{'fvd'}->{'over_time'} = $config->{'monitoring'}->{'fvd'}->{'over_seconds'};
    $self->{'fvd'}->{'over_value'} = $config->{'monitoring'}->{'fvd'}->{'over_value'};
    $self->{'fvd'}->{'under_time'} = $config->{'monitoring'}->{'fvd'}->{'under_seconds'};
    $self->{'fvd'}->{'under_value'} = $config->{'monitoring'}->{'fvd'}->{'under_value'};
    $self->{'fvd'}->{'status'} = OESS_LOAD_UNKNOWN;

    $self->{'nox'}->{'over_time'} = $config->{'monitoring'}->{'nox'}->{'over_seconds'};
    $self->{'nox'}->{'over_value'} = $config->{'monitoring'}->{'nox'}->{'over_value'};
    $self->{'nox'}->{'under_time'} = $config->{'monitoring'}->{'nox'}->{'under_seconds'};
    $self->{'nox'}->{'under_value'} = $config->{'monitoring'}->{'nox'}->{'under_value'};
    $self->{'nox'}->{'status'} = OESS_LOAD_UNKNOWN;

    $self->{'vlan_stats'}->{'over_time'} = $config->{'monitoring'}->{'vlan_stats'}->{'over_seconds'};
    $self->{'vlan_stats'}->{'over_value'} = $config->{'monitoring'}->{'vlan_stats'}->{'over_value'};
    $self->{'vlan_stats'}->{'under_time'} = $config->{'monitoring'}->{'vlan_stats'}->{'under_seconds'};
    $self->{'vlan_stats'}->{'under_value'} = $config->{'monitoring'}->{'vlan_stats'}->{'under_value'};
    $self->{'vlan_stats'}->{'status'} = OESS_LOAD_UNKNOWN;
}

=head2 do_work

does the actual monitoring and processing of each process and raises the
is overloaded flag

=cut

sub do_work{
    my $self = shift;
    $self->{'logger'}->debug("Running watchdog");
    
    #associate a process to a pid
    $self->get_processes();
    
    #do some work
    $self->monitor_process_cpu('fvd');
    $self->monitor_process_cpu('vlan_stats');
    $self->monitor_process_cpu('nox');
    
    #check the resulting status
    if($self->{'fvd'}->{'status'} == OESS_OVERLOADED){
        if(-e WATCHDOG_FILE){
            $self->{'logger'}->debug("system is already signaled overloaded");
        }else{
            $self->{'logger'}->warn("Forwarding Verification determined to be overloaded!");
            my $cmd = 'touch ' . WATCHDOG_FILE;
            `$cmd`;
        }
    }
    
    #check the resulting status
    if($self->{'vlan_stats'}->{'status'} == OESS_OVERLOADED){
        if(-e WATCHDOG_FILE){
            $self->{'logger'}->debug("system is already signaled overloaded");
        }else{
            $self->{'logger'}->warn("VLAN Stats determined to be overloaded!");
            my $cmd = 'touch ' . WATCHDOG_FILE;
            `$cmd`;
        }
    }
    
        #check the resulting status
    if($self->{'nox'}->{'status'} == OESS_OVERLOADED){
        if(-e WATCHDOG_FILE){
            $self->{'logger'}->debug("system is already signaled overloaded");
        }else{
            $self->{'logger'}->warn("NOX determined to be overloaded!");
            my $cmd = 'touch ' . WATCHDOG_FILE;
            `$cmd`;
        }
    }

    #check for recovery
    if($self->{'vlan_stats'}->{'status'} != OESS_OVERLOADED &&
       $self->{'fvd'}->{'status'} != OESS_OVERLOADED &&
       $self->{'nox'}->{'status'} != OESS_OVERLOADED){
        $self->{'logger'}->debug("System is in OK State.. verify no lock file exists");
        if(-e WATCHDOG_FILE){
                #we are recovered remove this file
            my $cmd = 'rm ' . WATCHDOG_FILE;
            `$cmd`;
        }
    }
    return;
}


=head2 get_processes

returns the processes that we are concerned about

=cut

sub get_processes{
    my $self = shift;
    my $table = $self->{'proc_table'}->table;
    $self->{'fvd'}->{'process'} = undef;
    $self->{'vlan_stats'}->{'process'} = undef;
    $self->{'nox'}->{'process'} = undef;
    foreach my $process (@$table){
        
        $self->{'logger'}->debug("Process: " . Data::Dumper::Dumper($process));

        switch($process->{'fname'}){
            case 'oess-fvd.pl'{
                $self->{'fvd'}->{'process'} = $process;
            }
            case 'vlan_stats_d.pl'{
                $self->{'vlan_stats'}->{'process'} = $process;
            }
            case 'nox_core'{
                $self->{'nox'}->{'process'} = $process;
            }else{
                next;
            }
        }
    }

    if(!defined($self->{'vlan_stats'}->{'process'})){
        $self->{'logger'}->error("Unable to find a process called 'vlan_stats_d.pl'");
    }

    if(!defined($self->{'nox'}->{'process'})){
        $self->{'logger'}->error("Unable to find a process called 'nox_cored'");
    }

    if(!defined($self->{'fvd'}->{'process'})){
        $self->{'logger'}->error("Unable to find a process called 'oess-fvd.pl'");
    }

}

=head2 monitor_process_cpu

monitors a processes cpu utilization and sets the is overloaded flag for
each process individually

=cut


sub monitor_process_cpu{
    my $self = shift;
    my $process_name = shift;
    
    if(!defined($self->{$process_name}->{'process'})){
        $self->{$process_name}->{'status'} = OESS_LOAD_UNKNOWN;
        return;
    }

    if($#{$self->{$process_name}->{'history'}} >= 1000){
        my $tmp = shift @{$self->{$process_name}->{'history'}};
    }

    my $usage = $self->_get_process_usage($self->{$process_name}->{'process'});

    $self->{'logger'}->debug($process_name . " running at: " . $usage ." util");
    push(@{$self->{$process_name}->{'history'}},$usage);

    if($self->{$process_name}->{'status'} == OESS_OVERLOADED){

        if($self->_is_under(history => $self->{$process_name}->{'history'},
                            under_time => $self->{$process_name}->{'under_time'},
                            under_value => $self->{$process_name}->{'under_value'})){
            $self->{'logger'}->warn("Forwarding Verification is no longer considered overloaded... setting to recovered");
            $self->{$process_name}->{'status'} = OESS_LOAD_OK;
        }else{
            $self->{'logger'}->debug("Forwarding verification is still overloaded");
        }

    }else{

        if($self->_is_over(history => $self->{$process_name}->{'history'},
                           over_time => $self->{$process_name}->{'over_time'},
                           over_value => $self->{$process_name}->{'over_value'})){
            $self->{'logger'}->warn("Forwarding Verification has exceeded threshold, and is considered overloaded");
            $self->{$process_name}->{'status'} = OESS_OVERLOADED;
        }else{
            $self->{'logger'}->debug("Forwarding verification operating as expected");
        }
    }
    
}


sub _is_over{
    my $self = shift;
    my %params = @_;

    my $history = $params{'history'};
    my $over_time = $params{'over_time'};
    my $over_value = $params{'over_value'};

    my $total_samples = $over_time / $self->{'interval'};
    $self->{'logger'}->debug("total samples: " . $total_samples);

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

sub _is_under{
    my $self = shift;
    my %params = @_;
    my $history = $params{'history'};
    my $under_time = $params{'under_time'};
    my $under_value = $params{'under_value'};

    my $total_samples = $under_time / $self->{'interval'};

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

sub _get_process_usage{
    my $self = shift;
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

    return undef;
}


1;
