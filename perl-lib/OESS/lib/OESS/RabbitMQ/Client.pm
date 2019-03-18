#!/usr/bin/perl

use strict;
use warnings;
use GRNOC::RabbitMQ::Client;
use GRNOC::Config;

package OESS::RabbitMQ::Client;

=head2 new

creates a new GRNOC::RabbitMQ module with all the OESS params

=cut

sub new{
    my $that = shift;
    my $class = ref($that) || $that;

    my %args = (
        timeout => 15,
        config  => '/etc/oess/database.xml',
        @_
    );

    if (!defined $args{'timeout'}) {
        $args{'timeout'} = 15;
    }
    
    my $config = GRNOC::Config->new(config_file => $args{'config'});
    
    my $user = $config->get('/config/rabbitMQ/@user')->[0];
    my $pass = $config->get('/config/rabbitMQ/@pass')->[0];
    my $host = $config->get('/config/rabbitMQ/@host')->[0];
    my $port = $config->get('/config/rabbitMQ/@port')->[0];

    my $rabbit = GRNOC::RabbitMQ::Client->new( host => $host,
					       pass => $pass,
					       user => $user,
					       port => $port,
					       timeout => $args{'timeout'},
					       exchange => 'OESS',
					       topic => $args{'topic'},
					       queue => $args{'queue'} );

    return $rabbit;

}

1;


