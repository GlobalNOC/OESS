#!/usr/bin/perl

use strict;
use warnings;

package OESS::RabbitMQ::RPC::Client;

use AnyEvent::RabbitMQ;
use AnyEvent;
use Data::UUID;
use Log::Log4perl;
use JSON::XS;

sub new{
    my $class = shift;
    
    my %args = ( host => 'localhost',
		 port => 5672,
		 user => undef,
		 pass => undef,
		 vhost => '/',
		 timeout => 1,
		 queue => undef,
		 exchange => 'OESS',
		 @_ );

    my $self = \%args;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.FWDCTL.MASTER');

    $self->{'uuid'} = new Data::UUID;
    bless $self, $class;
    
    $self->_connect();

    return $self;
}

sub _connect{
    my $self = shift;

    $self->{'logger'}->debug("Connecting to RabbitMQ");

    my $cv = AnyEvent->condvar;
    my $rabbit_mq;
    my $ar = AnyEvent::RabbitMQ->new->load_xml_spec()->connect(
	host => $self->{'host'},
	port => $self->{'port'},
	user => $self->{'user'},
	pass => $self->{'pass'},
	vhost => $self->{'vhost'},
	timeout => $self->{'timeout'},
	tls => 0,
	on_success => sub {
	    my $r = shift;
	    $r->open_channel(
		on_success => sub {
		    my $channel = shift;
		    $rabbit_mq = $channel;
		    $channel->declare_exchange(
			exchange   => $self->{'exchange'},
			type => 'topic',
			on_success => sub {
			    $cv->send();
			},
			on_failure => $cv,
			);
		},
		on_failure => $cv,
		on_close   => sub {
		    $self->{'logger'}->error("Disconnected from RabbitMQ!");
		},
		);
	},
	on_failure => $cv,
	on_read_failure => sub { die @_ },
	on_return  => sub {
	    my $frame = shift;
	    die "Unable to deliver ", Dumper($frame);
	},
	on_close   => sub {
	    my $why = shift;
	    if (ref($why)) {
		my $method_frame = $why->method_frame;
		die $method_frame->reply_code, ": ", $method_frame->reply_text;
	    }
	    else {
		die $why;
	    }
	}
	);
    
    #synchronize
    $cv->recv();

    $self->{'logger'}->debug("");

    $cv = AnyEvent->condvar;

    $self->{'ar'} = $ar;
    $self->{'rabbit_mq'} = $rabbit_mq;
    $self->{'rabbit_mq'}->declare_queue( exclusive => 1,
					 on_success => sub {
					     my $queue = shift;
					     $self->{'rabbit_mq'}->bind_queue( exchange => $self->{'exchange'},
									       queue => $queue->{method_frame}->{queue},
									       routing_key => $queue->{method_frame}->{queue},
									       on_success => sub {
										   $cv->send($queue->{method_frame}->{queue});
									       });
					 });
    
    my $cbq = $cv->recv();
    $self->{'callback_queue'} = $cbq;

    return;
}

sub _generate_uuid{
    my $self = shift;
    return $self->{'uuid'}->to_string($self->{'uuid'}->create());
}

sub AUTOLOAD{
    my $self = shift;

    my $name = our $AUTOLOAD;

    my @stuff = split('::', $name);
    $name = pop(@stuff);

    my $params = {
	@_
    };

    my $cv = AnyEvent->condvar;
    my $corr_id = $self->_generate_uuid();

    sub on_response_cb {
        my %a   = (
            condvar         => undef,
            correlation_id  => undef,
            @_
        );
        return  sub {
            my $var = shift;
            my $body = $var->{body}->{payload};
            if ($a{correlation_id} eq $var->{header}->{correlation_id}) {
                $a{condvar}->send($body);
            }
        };
    }

    $self->{'rabbit_mq'}->consume(
        no_ack => 1,
        on_consume => on_response_cb(
            condvar         => $cv,
            correlation_id  => $corr_id,
        ),
    );

    $self->{'rabbit_mq'}->publish(
        exchange => $self->{'exchange'},
        routing_key => $self->{'queue'} . "." . $name,
        header => {
            reply_to => $self->{'callback_queue'},
            correlation_id => $corr_id,
        },
        body => encode_json($params)
    );

    my $res = $cv->recv;
    return decode_json($res);
}

sub DESTROY{

}

1;
