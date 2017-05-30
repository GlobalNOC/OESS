#!/usr/bin/perl
#
##----- D-Bus OESS NSI Daemon
##-----
##----- Handles NSI Requests
#---------------------------------------------------------------------
#
# Copyright 2015 Trustees of Indiana University
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

package OESS::NSI::Daemon;
$ENV{CRYPT_SSLEAY_CIPHER} = 'ALL';
use strict;
use warnings;

use OESS::DBus;
use OESS::NSI::MessageQueue;
use OESS::NSI::Processor;

use GRNOC::Log;
use GRNOC::Config;
use GRNOC::WebService::Client;

use AnyEvent;
use Data::Dumper;
use Proc::Daemon;

use constant DEFAULT_PID_FILE => '/var/run/oess/oess-nsi.pid';

our $VERSION = '0.0.1';

=head2 new

=cut

sub new {
    my $caller = shift;

    my $class = ref($caller);
    $class = $caller if(!$class);

    my $self = {
        'config_file' => undef,
        'pid_file' => DEFAULT_PID_FILE,
        'daemonize' => 1,
        'running' => 0,
        'hup' => 0,
        @_
    };

    bless($self,$class);

    $self->{'logger'} = GRNOC::Log->new(config => '/etc/grnoc/logging.conf');
    return $self;
}

=head2 start

=cut


sub start {
    my ($self) = shift;

    log_info("Starting OESS NSI Daemon");

    if($self->{'daemonize'}){
        log_info("Spawning as Daemon Process");
        my $daemon = new Proc::Daemon(
            'pid_file' => $self->{'pid_file'}
            );

        my $pid = $daemon->init();

        if(!$pid){
            $0 = "oess-nsi-daemon";

            $SIG{'TERM'} = sub {$self->stop();};
            $SIG{'HUP'} = sub {$self->hup();};

            $self->_run();
        }
    }
    else{
        log_info("Spawning in foreground");
        $self->{'running'} = 1;
        $self->_run();
    }
}

=head2 stop

=cut

sub stop {
    my ($self) = @_;

    log_info("Stopping");
}

=head2 hup

=cut

sub hup {
    my ($self) = @_;

    log_info("HUP Request Received");
    $self->{'processor'}->hup();
}

sub _process_queues {
    my $self = shift;

    $self->{'processor'}->process_queues();
}

sub _run {
    my ($self) = @_;

    $self->{'processor'} = new OESS::NSI::Processor(undef, $self->{'config_file'});
    log_info("NSI event processor was created.");


    # TODO: The process_queues_handler probably isn't needed. Instead
    # $self->{'processor'}->process_queues should be called once every
    # ten seconds.
    eval {
        $self->{'mqueue'} = new OESS::NSI::MessageQueue(
            user     => 'guest',
            pass     => 'guest',
            exchange => 'OESS',
            provision_event_handler => sub { $self->{'processor'}->circuit_provision(@_); },
            modified_event_handler  => sub { $self->{'processor'}->circuit_modified(@_); },
            removed_event_handler   => sub { $self->{'processor'}->circuit_removed(@_); },
            process_request_handler => sub { $self->{'processor'}->process_request(@_); }
        );
    };
    if ($@) {
        log_error("An error occurred while creating RabbitMQ interface: " . "$@");
        return undef;
    }

    my $queue_timer = AnyEvent->timer(after => 3, interval => 10, cb => sub { $self->{'processor'}->process_queues(@_); });

    log_info("NSI daemon is now starting.");
    $self->{'mqueue'}->start();
}

1;
