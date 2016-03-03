#!/usr/bin/python

import time
import pika
import sys
import json
import logging
import threading

logger = logging.getLogger('org.nddi.openflow.rmqi')

class RMQI(threading.Thread):
    def __init__(self, **kwargs):
        super(RMQI, self).__init__()
       
        self.signal_callbacks = {}
    
        self.host          = kwargs.get('host', '127.0.0.1')
        self.port          = kwargs.get('port', 5672)
        self.virtual_host  = kwargs.get('virtual_host', '/')
        self.username      = kwargs.get('username', 'guest')
        self.password      = kwargs.get('password', 'guest')
        self.exchange      = kwargs.get('exchange')
        self.queue         = kwargs.get('queue')
        self.exchange_type = 'topic'

        if(self.exchange is None):
            print 'Must pass in exchange!'
            sys.exit(1)
        if(self.queue is None):
            print 'Must pass in queue!'
            sys.exit(1)
        
        # create our connection and channel 
        self.amqp_url     = 'amqp://{0}:{1}@{2}:{3}/%2F'.format(self.username, self.password, self.host, self.port)
        self.channel      = None
        self.closing      = False
        self.consumer_tag = None
        self.queue_declared = False

    def on_request(self, ch, method, props, body):
        routing_key = method.routing_key

        logger.warn("in on_request with body: {0}".format(body))

        if(self.signal_callbacks[routing_key] is None):
            logger.info("No callbacks registered for, {0}".format(routing_key))

        # get our result back from the callback corresponding to this routing_key
        result = None
        try:
            args = json.loads(body)
            logger.warn("calling {0} with {1}".format(routing_key, args))
            result = (self.signal_callbacks[routing_key])(**args)
        except Exception as e:
            logger.warn('error calling {0}: {1}'.format(routing_key, e))
            result = {
                'error': 1,
                'error_txt': "Error calling {0}: {1}".format(routing_key, e)
            }

        # reply to the reply queue and ack if the no_reply header was not sent
        if(props.headers.get('no_reply') != 1):
            print "replying..."
            ch.basic_publish(
                exchange=self.exchange,
                routing_key=props.reply_to,
                properties=pika.BasicProperties(
                    correlation_id = props.correlation_id
                ),
                body=self._encode_json(result)
            )

        ch.basic_ack(delivery_tag=method.delivery_tag)

    def _encode_json(self, result, signal=False):
        if signal: # Signals must have no 'results' array
            return json.JSONEncoder().encode(result)

        # if a result is returned try to decode it otherwise just send an 
        # empty result object back
        json_result = '{ "results": [] }'
        if(result is not None): 
            # if result is not an array make it one
            if(not isinstance(result, list)):
                result = [result]

            result = {
                'results': result
            }
            json_result = json.JSONEncoder().encode(result)

        return json_result

    def emit_signal(self, signal_name, **kwargs):
        print "Emitting signal!!!! with: {0}".format(kwargs)
        self.channel.basic_publish(
            exchange=self.exchange,
            routing_key='{0}.{1}'.format(self.queue, signal_name),
            body=self._encode_json(kwargs, signal=True),
            properties=pika.BasicProperties(
                headers={
                    'no_reply': 1
                }
            )
        )

    def subscribe_to_signal(self, **kwargs):
        try: 
            method = kwargs.get('method')
            method_name = method.__name__
            print "registering callback to signal/method: {0}".format(method_name)
        except Exception as e:
            print "Must provide method_name to register rpc method: {0}".format(e)
            sys.exit(1)

        routing_key = '{0}.{1}'.format(self.queue, method_name)
        logger.warn('RMQI subscribing to: {0}'.format(routing_key))

        # add this this callback
        self.signal_callbacks[routing_key] = method


    def connect(self):
        """This method connects to RabbitMQ, returning the connection handle.
        When the connection is established, the on_connection_open method
        will be invoked by pika.

        :rtype: pika.SelectConnection

        """
        logger.info('RMQI Connecting to RabbitMQ...')
        print "about to connect..."

        self.connection = pika.SelectConnection(
            pika.URLParameters(self.amqp_url),
            self.on_connection_open,
            stop_ioloop_on_close=False
        )
        self.connection.ioloop.start()


    def on_connection_open(self, unused_connection):
        """This method is called by pika once the connection to RabbitMQ has
        been established. It passes the handle to the connection object in
        case we need it, but in this case, we'll just mark it unused.

        :type unused_connection: pika.SelectConnection

        """
        print "established connection"
        logger.info('Connection opened')
        self.add_on_connection_close_callback()
        self.open_channel()
        self.connected = True

    def add_on_connection_close_callback(self):
        """This method adds an on close callback that will be invoked by pika
        when RabbitMQ closes the connection to the publisher unexpectedly.

        """
        logger.info('Adding connection close callback')
        self.connection.add_on_close_callback(self.on_connection_closed)

    def on_connection_closed(self, connection, reply_code, reply_text):
        """This method is invoked by pika when the connection to RabbitMQ is
        closed unexpectedly. Since it is unexpected, we will reconnect to
        RabbitMQ if it disconnects.

        :param pika.connection.Connection connection: The closed connection obj
        :param int reply_code: The server provided reply_code if given
        :param str reply_text: The server provided reply_text if given

        """
        self.channel = None
        if self.closing:
            self.connection.ioloop.stop()
        else:
            logger.warning('Connection closed, reopening in 5 seconds: (%s) %s',
                           reply_code, reply_text)
            self.connection.add_timeout(5, self.reconnect)

    def reconnect(self):
        """Will be invoked by the IOLoop timer if the connection is
        closed. See the on_connection_closed method.

        """
        # This is the old connection IOLoop instance, stop its ioloop
        self.connection.ioloop.stop()

        if not self.closing:

            # Create a new connection
            self.connect()

            # There is now a new connection, needs a new ioloop to run
            self.connection.ioloop.start()

    def open_channel(self):
        """Open a new channel with RabbitMQ by issuing the Channel.Open RPC
        command. When RabbitMQ responds that the channel is open, the
        on_channel_open callback will be invoked by pika.

        """
        logger.info('Creating a new channel')
        self.connection.channel(on_open_callback=self.on_channel_open)

    def on_channel_open(self, channel):
        """This method is invoked by pika when the channel has been opened.
        The channel object is passed in so we can make use of it.

        Since the channel is now open, we'll declare the exchange to use.

        :param pika.channel.Channel channel: The channel object

        """
        logger.info('Channel opened')
        print "channel opened"
        self.channel = channel
        self.add_on_channel_close_callback()
        self.setup_exchange(self.exchange)

    def add_on_channel_close_callback(self):
        """This method tells pika to call the on_channel_closed method if
        RabbitMQ unexpectedly closes the channel.

        """
        logger.info('Adding channel close callback')
        self.channel.add_on_close_callback(self.on_channel_closed)

    def on_channel_closed(self, channel, reply_code, reply_text):
        """Invoked by pika when RabbitMQ unexpectedly closes the channel.
        Channels are usually closed if you attempt to do something that
        violates the protocol, such as re-declare an exchange or queue with
        different parameters. In this case, we'll close the connection
        to shutdown the object.

        :param pika.channel.Channel: The closed channel
        :param int reply_code: The numeric reason the channel was closed
        :param str reply_text: The text reason the channel was closed

        """
        logger.warning('Channel %i was closed: (%s) %s',
                       channel, reply_code, reply_text)
        self.connection.close()

    def setup_exchange(self, exchange_name):
        """Setup the exchange on RabbitMQ by invoking the Exchange.Declare RPC
        command. When it is complete, the on_exchange_declareok method will
        be invoked by pika.

        :param str|unicode exchange_name: The name of the exchange to declare

        """
        logger.info('Declaring exchange %s', exchange_name)
        self.channel.exchange_declare(self.on_exchange_declareok,
                                       exchange_name,
                                       self.exchange_type)

    def on_exchange_declareok(self, unused_frame):
        """Invoked by pika when RabbitMQ has finished the Exchange.Declare RPC
        command.

        :param pika.Frame.Method unused_frame: Exchange.DeclareOk response frame

        """
        logger.info('Exchange declared')
        self.setup_queue(self.queue)

    def setup_queue(self, queue_name):
        """Setup the queue on RabbitMQ by invoking the Queue.Declare RPC
        command. When it is complete, the on_queue_declareok method will
        be invoked by pika.

        :param str|unicode queue_name: The name of the queue to declare.

        """
        logger.info('Declaring queue %s', queue_name)
        print "Setting up queue"
        self.channel.queue_declare(self.on_queue_declareok, queue_name)

    def on_queue_declareok(self, method_frame):
        """Method invoked by pika when the Queue.Declare RPC call made in
        setup_queue has completed. In this method we will bind the queue
        and exchange together with the routing key by issuing the Queue.Bind
        RPC command. When this command is complete, the on_bindok method will
        be invoked by pika.

        :param pika.frame.Method method_frame: The Queue.DeclareOk frame

        """
        logger.info('Queue, {0}, successfully declared'.format(self.exchange, self.queue))

        for routing_key in self.signal_callbacks:
            logger.info("Binding to {0}:{1}:{2}".format(self.exchange, self.queue, routing_key))
            self.channel.queue_bind(self.on_bindok, self.queue, self.exchange,
                routing_key=routing_key
            )

    def on_bindok(self, unused_frame):

        """Invoked by pika when the Queue.Bind method has completed. At this
        point we will start consuming messages by calling start_consuming
        which will invoke the needed RPC commands to start the process.

        :param pika.frame.Method unused_frame: The Queue.BindOk response frame

        """
        logger.info('Queue bound')
        self.queue_declared = True
        self.consumer_tag = self.channel.basic_consume(self.on_request, self.queue)

    def add_on_cancel_callback(self):
        """Add a callback that will be invoked if RabbitMQ cancels the consumer
        for some reason. If RabbitMQ does cancel the consumer,
        on_consumer_cancelled will be invoked by pika.

        """
        logger.info('Adding consumer cancellation callback')
        self.channel.add_on_cancel_callback(self.on_consumer_cancelled)

    def on_consumer_cancelled(self, method_frame):
        """Invoked by pika when RabbitMQ sends a Basic.Cancel for a consumer
        receiving messages.

        :param pika.frame.Method method_frame: The Basic.Cancel frame

        """
        logger.info('Consumer was cancelled remotely, shutting down: %r',
                    method_frame)
        if self.channel:
            self.channel.close()

    def acknowledge_message(self, delivery_tag):
        """Acknowledge the message delivery from RabbitMQ by sending a
        Basic.Ack RPC method for the delivery tag.

        :param int delivery_tag: The delivery tag from the Basic.Deliver frame

        """
        logger.info('Acknowledging message %s', delivery_tag)
        self.channel.basic_ack(delivery_tag)

    def stop_consuming(self):
        """Tell RabbitMQ that you would like to stop consuming by sending the
        Basic.Cancel RPC command.

        """
        if self.channel:
            logger.info('Sending a Basic.Cancel RPC command to RabbitMQ')
            self.channel.basic_cancel(self.on_cancelok, self.consumer_tag)

    def on_cancelok(self, unused_frame):
        """This method is invoked by pika when RabbitMQ acknowledges the
        cancellation of a consumer. At this point we will close the channel.
        This will invoke the on_channel_closed method once the channel has been
        closed, which will in-turn close the connection.

        :param pika.frame.Method unused_frame: The Basic.CancelOk frame

        """
        logger.info('RabbitMQ acknowledged the cancellation of the consumer')
        self.close_channel()

    def close_channel(self):
        """Call to close the channel with RabbitMQ cleanly by issuing the
        Channel.Close RPC command.

        """
        logger.info('Closing the channel')
        self.channel.close()

    def run(self):
        self.connect()

    def stop(self):
        """Cleanly shutdown the connection to RabbitMQ by stopping the consumer
        with RabbitMQ. When RabbitMQ confirms the cancellation, on_cancelok
        will be invoked by pika, which will then closing the channel and
        connection. The IOLoop is started again because this method is invoked
        when CTRL-C is pressed raising a KeyboardInterrupt exception. This
        exception stops the IOLoop which needs to be running for pika to
        communicate with RabbitMQ. All of the commands issued prior to starting
        the IOLoop will be buffered but not processed.

        """
        logger.info('Stopping')
        self.closing = True
        self.stop_consuming()
        self.connection.ioloop.start()
        logger.info('Stopped')

    def close_connection(self):
        """This method closes the connection to RabbitMQ."""
        logger.info('Closing connection')
        self.connection.close()

