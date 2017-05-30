#!/usr/bin/perl

use strict;
use warnings;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::Config;

package OESS::RabbitMQ::Dispatcher;

=head2 new

Creates a Dispatcher. For this application exclusive queues are used
(used by only 1 connection and deleted on connection closed).

=cut
sub new{
    my $that = shift;
    my $class = ref($that) || $that;

    my %args = (
        timeout => 15,
        @_
    );

    if (!defined $args{'timeout'}) {
        $args{'timeout'} = 15;
    }

    my $config = GRNOC::Config->new(config_file => '/etc/oess/database.xml');
    
    my $user = $config->get('/config/rabbitMQ/@user')->[0];
    my $pass = $config->get('/config/rabbitMQ/@pass')->[0];
    my $host = $config->get('/config/rabbitMQ/@host')->[0];
    my $port = $config->get('/config/rabbitMQ/@port')->[0];

    my $rabbit = GRNOC::RabbitMQ::Dispatcher->new(
        host => $host,
        pass => $pass,
        user => $user,
        port => $port,
        timeout => $args{'timeout'},
        exchange => 'OESS',
        topic => $args{'topic'},
        queue => $args{'queue'},
        exclusive => 1
    );
    
    return $rabbit;

}

1;
