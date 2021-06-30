#!/usr/bin/perl
use strict;
use warnings;

use OESS::Config;
use OESS::MPLS::FWDCTL;
use OESS::NSO::FWDCTLService;

use English;
use Data::Dumper;
use Getopt::Long;
use Log::Log4perl;
use Proc::Daemon;
use XML::Simple;

my $pid_file = "/var/run/oess/mpls_fwdctl.pid";
my $cnf_file = "/etc/oess/database.xml";

sub get_diff_interval{
    eval {
        my $xml = XMLin('/etc/oess/fwdctl.xml');
        my $diff_interval = $xml->{diff}->{interval};
        die unless defined $diff_interval;
        return $diff_interval;
    } or do {
        return 900;
    }
}

sub core{
    Log::Log4perl::init_and_watch('/etc/oess/logging.conf', 10);

    my $config = new OESS::Config(config_filename => $cnf_file);
    if ($config->network_type eq 'nso') {
        my $fwdctl = OESS::NSO::FWDCTLService->new(config_obj => $config);
        $fwdctl->start;
        AnyEvent->condvar->recv;
    }
    elsif ($config->network_type eq 'vpn-mpls' || $config->network_type eq 'evpn-vxlan') {
        my $FWDCTL = OESS::MPLS::FWDCTL->new(config_obj => $config);
        my $reaper = AnyEvent->timer( after => 3600, interval => 3600, cb => sub { $FWDCTL->reap_old_events() } );
        my $status = AnyEvent->timer( after => 10, interval => 60, cb => sub { $FWDCTL->save_mpls_nodes_status() } );
        my $differ = AnyEvent->timer( after => 5, interval => get_diff_interval(), cb => sub { $FWDCTL->diff() } );
        AnyEvent->condvar->recv;
    }
    elsif ($config->network_type eq 'nso+vpn-mpls') {
        my $fwdctl = OESS::NSO::FWDCTLService->new(config_obj => $config);
        $fwdctl->start;

        my $FWDCTL = OESS::MPLS::FWDCTL->new(config_obj => $config);
        my $reaper = AnyEvent->timer( after => 3600, interval => 3600, cb => sub { $FWDCTL->reap_old_events() } );
        my $status = AnyEvent->timer( after => 10, interval => 60, cb => sub { $FWDCTL->save_mpls_nodes_status() } );
        my $differ = AnyEvent->timer( after => 5, interval => get_diff_interval(), cb => sub { $FWDCTL->diff() } );
        AnyEvent->condvar->recv;
    }
    else {
        die "Unexpected network type configured.";
    }

    Log::Log4perl->get_logger('OESS.MPLS.FWDCTL.APP')->info("Starting OESS.MPLS.FWDCTL event loop.");
}

sub main{
    my $is_daemon = 0;
    my $verbose;
    my $username;
    #remove the ready file

    # This directory is auto-removed on reboot. Create the directory if not
    # already created. This is used to store connection cache files.
    if (!-d "/var/run/oess/") {
        `/usr/bin/mkdir /var/run/oess`;
        `/usr/bin/chown _oess:_oess /var/run/oess`;
    }

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
                                        child_STDOUT => '/var/log/oess/mpls_fwdctl.out',
                                        child_STDERR => '/var/log/oess/mpls_fwdctl.log',
		);
        } else {
            $daemon = Proc::Daemon->new(
		pid_file => $pid_file
		);
        }
	
        # Init returns the PID (scalar) of the daemon to the parent, or
        # the PIDs (array) of the daemons created if exec_command has
        # more then one program to execute.
        #
        # Init returns 0 to the child (daemon).
        my $kid_pid = $daemon->Init;
        if ($kid_pid) {
            `chmod 0644 $pid_file`; # How to wait until the child process is ready.
            return;
        } else {
            core();
        }
    }
    #not a daemon, just run the core;
    else {
        $SIG{HUP} = sub{ exit(0); };
        core();
    }

}

main();

1;
