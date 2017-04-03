package OESS::NSI::MessageQueue;

use strict;
use warnings;

use Data::Dumper;

use GRNOC::Log;
use GRNOC::Config;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use GRNOC::WebService::Regex;

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

    $self->{'router'} = GRNOC::RabbitMQ::Dispatcher->new(
        user     => $self->{'user'},
        pass     => $self->{'pass'},
        exchange => $self->{'exchange'},
        topic    => 'OESS.NSI.Processor',
        queue    => 'OESS.NSI.Processor'
    );

    my $method;
    $method = GRNOC::RabbitMQ::Method->new(name        => 'circuit_provision',
                                           async       => 1,
                                           topic       => 'OF.Notification.event',
                                           callback    => $self->{'provision_event_handler'},
                                           description => 'Handles provisioned circuit events');
    $method->add_input_parameter(name        => 'circuit_id',
                                 description => 'The events associated circuit',
                                 pattern     => $GRNOC::WebService::Regex::INTEGER);
    $self->{'router'}->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(name        => 'circuit_modify',
                                           async       => 1,
                                           topic       => 'OF.Notification.event',
                                           callback    => $self->{'modified_event_handler'},
                                           description => 'Handles modified circuit events');
    $method->add_input_parameter(name        => 'circuit_id',
                                 description => 'The events associated circuit',
                                 pattern     => $GRNOC::WebService::Regex::INTEGER);
    $self->{'router'}->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(name        => 'circuit_remove',
                                           async       => 1,
                                           topic       => 'OF.Notification.event',
                                           callback    => $self->{'removed_event_handler'},
                                           description => 'Handles removed circuit events');
    $method->add_input_parameter(name        => 'circuit_id',
                                 description => 'The events associated circuit',
                                 pattern     => $GRNOC::WebService::Regex::INTEGER);
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

    return $self;
}

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
