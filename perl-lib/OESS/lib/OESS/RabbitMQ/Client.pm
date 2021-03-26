#!/usr/bin/perl

use strict;
use warnings;
use GRNOC::RabbitMQ::Client;
use OESS::Config;

package OESS::RabbitMQ::Client;

=head2 new

new creates a new GRNOC::RabbitMQ module with all the OESS params

=cut
sub new {
    my $that = shift;
    my $class = ref($that) || $that;

    my %args = (
        timeout    => 15,
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
    
    my $rabbit = GRNOC::RabbitMQ::Client->new(
        user     => $config->rabbitmq_user,
        pass     => $config->rabbitmq_pass,
        host     => $config->rabbitmq_host,
        port     => $config->rabbitmq_port,
        exchange => 'OESS',
        timeout  => $args{'timeout'},
        topic    => $args{'topic'},
        queue    => $args{'queue'}
    );

    return $rabbit;
}

1;
