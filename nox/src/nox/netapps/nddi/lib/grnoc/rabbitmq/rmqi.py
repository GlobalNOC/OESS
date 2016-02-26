#!/usr/bin/python

import pika
import sys
import json

class RMQI():
    def __init__(self, **kwargs):
       
        self.signal_callbacks = {}
    
        host          = kwargs.get('host', '127.0.0.1')
        port          = kwargs.get('port', 5672)
        virtual_host  = kwargs.get('virtual_host', '/')
        username      = kwargs.get('username', 'guest')
        password      = kwargs.get('password', 'guest')
        self.exchange = kwargs.get('exchange')
        self.queue    = kwargs.get('queue')

        if(self.exchange is None):
            print 'Must pass in exchange!'
            sys.exit(1)
        if(self.queue is None):
            print 'Must pass in queue!'
            sys.exit(1)
        
        # create our connection and channel 
        self.connection = pika.BlockingConnection(pika.ConnectionParameters(
            host=host,
            port=port,
            virtual_host=virtual_host,
            credentials=pika.PlainCredentials(username, password)
        ))
        self.channel = self.connection.channel()
        self.channel.queue_declare(queue=self.queue)
        self.channel.exchange_declare(exchange=self.exchange, type='topic')
        self.channel.basic_qos(prefetch_count=1)

    def on_request(self, ch, method, props, body):
        routing_key = method.routing_key

        if(self.signal_callbacks[routing_key] is None):
            print "No callback registered for, {0}".format(routing_key)

        # get our result back from the callback corresponding to this routing_key
        result = None
        try:
            args = json.loads(body)
            print "args: {0}".format(args)
            result = self.signal_callbacks[routing_key](args)
        except Exception as e:
            print "Error calling {0}: {1}".format(routing_key, e)

        print "json: {0}".format(self._encode_json(result))
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

    def _encode_json(self, result):
        # if a result is returned try to decode it otherwise just send an 
        # empty result object back
        json_result = '{ "results": undef }'
        if(result is not None): 
            json_result = json.JSONEncoder().encode(result)

        return json_result

    def emit_signal(self, signal_name, **kwargs):
        self.channel.basic_publish(
            exchange=self.exchange,
            routing_key='{0}.{1}'.format(self.queue, signal_name),
            body=self._encode_json(kwargs),
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

        self.channel.queue_bind(
            exchange=self.exchange,
            queue=self.queue, 
            routing_key=routing_key
        )

        # add this this callback
        self.signal_callbacks[routing_key] = method

    def start_consuming(self):
        print "consuming messages..."
        self.channel.basic_consume(self.on_request, queue=self.queue)
        self.channel.start_consuming()

