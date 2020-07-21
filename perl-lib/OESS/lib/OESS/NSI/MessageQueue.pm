package OESS::NSI::MessageQueue;

use strict;
use warnings;

use Data::Dumper;

use GRNOC::Log;
use GRNOC::Config;
use OESS::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use GRNOC::WebService::Regex;

=head2 new

=cut

sub new {
    my $class = shift;
    $class = ref($class) || $class;

    my $self = {
        user     => undef,
        pass     => undef,
        exchange => 'OESS',
        provision_event_handler => sub { warn('Not implemented.') },
        modified_event_handler  => sub { warn('Not implemented.') },
        removed_event_handler   => sub { warn('Not implemented.') },
        process_request_handler => sub { warn('Not implemented.') },
        process_queues_handler  => sub { warn('Not implemented.') },
        @_,
    };

    bless $self, $class;

    $self->{'log'} = GRNOC::Log->get_logger('OESS.NSI.MessageQueue');

    $self->{'router'} = OESS::RabbitMQ::Dispatcher->new( topic    => 'OESS.NSI.Processor',
							 queue    => 'OESS.NSI.Processor');

    my $method;
    $method = GRNOC::RabbitMQ::Method->new(name        => 'circuit_provision',
                                           async       => 1,
                                           topic       => 'OF.Notification.event',
                                           callback    => $self->{'provision_event_handler'},
                                           description => 'Handles provisioned circuit events');

    $method->add_input_parameter(name        => 'circuit',
                                 description => 'The events associated circuit',
                                 required => 1,
                                 schema => {'type' => 'object'});
    $self->{'router'}->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(name        => 'circuit_modify',
                                           async       => 1,
                                           topic       => 'OF.Notification.event',
                                           callback    => $self->{'modified_event_handler'},
                                           description => 'Handles modified circuit events');

    $method->add_input_parameter(name        => 'circuit',
                                 description => 'The events associated circuit',
                                 required => 1,
                                 schema => {'type' => 'object'});
    $self->{'router'}->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(name        => 'circuit_remove',
                                           async       => 1,
                                           topic       => 'OF.Notification.event',
                                           callback    => $self->{'removed_event_handler'},
                                           description => 'Handles removed circuit events');
    $method->add_input_parameter(name        => 'circuit',
                                 description => 'The events associated circuit',
                                 required => 1,
                                 schema => {'type' => 'object'});
    $self->{'router'}->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(name        => 'process_request',
                                           async       => 1,
                                           topic       => 'OESS.NSI.Processor',
                                           callback    => $self->{'process_request_handler'},
                                           description => 'Handles an NSI request');
    $method->add_input_parameter(name        => 'method',
                                 description => 'The NSI method to be called',
                                 pattern     => $GRNOC::WebService::Regex::TEXT);
    $method->add_input_parameter(name        => 'data',
                                 description => 'The params to pass to method',
                                 pattern     => $GRNOC::WebService::Regex::TEXT);
    $self->{'router'}->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(name        => 'process_queues',
                                           async       => 1,
                                           topic       => 'OESS.NSI.Processor',
                                           callback    => $self->{'process_queues_handler'},
                                           description => 'Processes accumulated NSI queues');
    $self->{'router'}->register_method($method);
    $method = GRNOC::RabbitMQ::Method->new(name        => 'is_online',
                                           async       => 1,
                                           topic       => 'OF.Notification.event',
                                           callback    => sub { my $method = shift;
                                                                $method->{'success_callback'}({successful => 1});
                                                            },
                                           description => 'Returns if the service is currently online.');
    $self->{'router'}->register_method($method);

    return $self;
}

=head2 start

=cut

sub start {
    my $self = shift;

    eval {
        $self->{'log'}->info("NSI provider agent now listening for requests via RabbitMQ.");
        $self->{'router'}->start_consuming();
    };
    if ($@) {
        $self->{'log'}->fatal("Failure in start consuming: $@");
        exit 1;
    }

    return 1;
}

=head2 stop

=cut

sub stop {
    my $self = shift;

    eval {
        $self->{'log'}->info("NSI provider agent stopped listening for requests.");
        $self->{'router'}->stop_consuming();
    };
    if ($@) {
        $self->{'log'}->fatal("Failure in stop consuming: $@");
        exit 1;
    }

    return 1;
}

1;
