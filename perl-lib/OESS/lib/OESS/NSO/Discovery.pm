use strict;
use warnings;

package OESS::NSO::Discovery;

use AnyEvent;
use Data::Dumper;
use GRNOC::RabbitMQ::Method;
use JSON;
use Log::Log4per;

use OESS::Config;
use OESS::DB;
use OESS::RabbitMQ::Dispatcher;

=head1 OESS::NSO::Discovery

=cut

=head2 new

=cut
sub new {
    my $class = shift;
    my $args  = {
        config => '/etc/oess/database.xml',
        logger => Log::Log4perl->get_logger('OESS.NSO.Discovery'),
        @_
    };
    my $self = bless $args, $class;

    $self->{config_filename} = $self->{config};
    $self->{config} = new OESS::Config(config_filename => $self->{config_filename});
    $self->{db} = new OESS::DB(config => $self->{config_filename});

    # When this process receives sigterm send an event to notify all
    # children to exit cleanly.
    $SIG{TERM} = sub {
        $self->stop;
    };

    return $self;
}

=head2 connection_handler

=cut
sub connection_handler {
    my $self = shift;

    return 1;
}

=head2 device_handler

=cut
sub device_handler {
    my $self = shift;

    return 1;
}

=head2 interface_handler

=cut
sub interface_handler {
    my $self = shift;

    return 1;
}

=head2 link_handler

=cut
sub link_handler {
    my $self = shift;

    return 1;
}

=head2 new_switch

=cut
sub new_switch {
    my $self = shift;

    return 1;
}

=head2 start

=cut
sub start {
    my $self = shift;

    $self->{connection_timer} = AnyEvent->timer(
        after    => 20,
        interval => 60,
        cb       => sub { $self->connection_handler(@_); }
    );
    $self->{device_timer} = AnyEvent->timer(
        after    => 10,
        interval => 60,
        cb       => sub { $self->device_handler(@_); }
    );
    $self->{interface_timer} = AnyEvent->timer(
        after    =>  60,
        interval => 120,
        cb       => sub { $self->interface_handler(@_); }
    );
    $self->{link_timer} = AnyEvent->timer(
        after    =>  80,
        interval => 120,
        cb       => sub { $self->link_handler(@_); }
    );

    $self->{dispatcher} = new OESS::RabbitMQ::Dispatcher(
        queue => 'oess-discovery',
        topic => 'oess.discovery.rpc'
    );

    my $new_switch = new GRNOC::RabbitMQ::Method(
        name        => 'new_switch',
        description => 'Add a new switch to the database',
        async       => 1,
        callback    => sub { $self->new_switch(@_); }
    );
    $new_switch->add_input_parameter(
        name        => 'node_id',
        description => 'Id of the new node',
        required    => 1,
        pattern     => $GRNOC::WebService::Regex::NUMBER_ID
    );
    $self->{dispatcher}->register_method($new_switch);

    my $is_online = new GRNOC::RabbitMQ::Method(
        name        => "is_online",
        description => 'Return if this service is online',
        async       => 1,
        callback    => sub {
            my $method = shift;
            return $method->{success_callback}({ successful => 1 });
        }
    );
    $self->{dispatcher}->register_method($is_online);

    $self->{dispatcher}->start_consuming;
    return 1;
}

=head2 stop

=cut
sub stop {
    my $self = shift;
    $self->{logger}->info('Stopping OESS::NSO::Discovery.');
    $self->{dispatcher}->stop_consuming;
}

1;
