#!/usr/bin/perl

use strict;
use warnings;
use GRNOC::RabbitMQ::Dispatcher;
use OESS::Config;

package OESS::RabbitMQ::Dispatcher;

=head2 new

new creates a Dispatcher. For this application exclusive queues are used
(used by only 1 connection and deleted on connection closed).

=cut
sub new {
    my $that = shift;
    my $class = ref($that) || $that;

    my %args = (
        timeout => 15,
        config     => '/etc/oess/database.xml',
        config_obj => undef,
        @_
    );

    if (!defined $args{'timeout'}) {
        $args{'timeout'} = 15;
    }

    my $config = $args{'config_obj'};
    if (!defined $config) {
        $config = new OESS::Config->new(config_file => $args{'config'});
    }

    my $rabbit = GRNOC::RabbitMQ::Dispatcher->new(
        user      => $config->rabbitmq_user,
        pass      => $config->rabbitmq_pass,
        host      => $config->rabbitmq_host,
        port      => $config->rabbitmq_port,
        exchange  => 'OESS',
        timeout   => $args{'timeout'},
        topic     => $args{'topic'},
        queue     => $args{'queue'},
        exclusive => 1
    );
    
    return $rabbit;
}

1;
