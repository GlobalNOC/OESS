#!/usr/bin/python

import time
import pika
import sys
import json
import logging

logger = logging.getLogger('org.nddi.openflow.rmqi')

class RMQI():
    def __init__(self, **kwargs):
        self.signal_callbacks = {}
    
        self.host          = kwargs.get('host', '127.0.0.1')
        self.port          = kwargs.get('port', 5672)
        self.virtual_host  = kwargs.get('virtual_host', '/')
        self.username      = kwargs.get('username', 'guest')
        self.password      = kwargs.get('password', 'guest')
        self.exchange      = kwargs.get('exchange')
        self.topic         = kwargs.get('topic')
        self.queue         = kwargs.get('queue')
        self.exchange_type = 'topic'
        
        if(self.exchange is None):
            print 'Must pass in exchange!'
            sys.exit(1)
        if(self.queue is None):
            print 'Must pass in queue!'
            sys.exit(1)
        if(self.topic is None):
            print 'Must pass in topic!'
            sys.exit(1)

        params = pika.connection.ConnectionParameters(
            host = self.host,
            port = self.port,
            virtual_host = self.virtual_host,
            credentials = pika.credentials.PlainCredentials( username = self.username,
                                                             password = self.password))

        self.connection = pika.BlockingConnection( parameters = params )
        
        self.channel = self.connection.channel()

        self.channel.queue_declare(queue=self.queue,
                                   exclusive=True,
                                   auto_delete=True
                                   )

        self.channel.exchange_declare( exchange = self.exchange,
                                       exchange_type = self.exchange_type )

    def fetch(self):
        
        (method, props, body) = self.channel.basic_get(queue=self.queue)       
        if(method == None):
            return
        logger.info("Received a request!!")
        logger.info(method)
        logger.info(props)
        logger.info(body)
        self.on_request(method, props, body)

    def on_request(self, method, props, body):
        routing_key = method.routing_key

        logger.debug("in on_request with body: {0}".format(body))

        if(self.signal_callbacks[routing_key] is None):
            logger.warn("No callbacks registered for, {0}".format(routing_key))

        # get our result back from the callback corresponding to this routing_key
        result = None
        try:
            args = json.loads(body)
            logger.debug("calling {0} with {1}".format(routing_key, args))
            result = (self.signal_callbacks[routing_key])(**args)
        except Exception as e:
            logger.warn('error calling {0}: {1}'.format(routing_key, e))
            result = {
                'error': 1,
                'error_txt': "Error calling {0}: {1}".format(routing_key, e)
            }

        # reply to the reply queue and ack if the no_reply header was not sent
        if(props.headers.get('no_reply') != 1):
            self.channel.basic_publish(
                self.exchange,
                props.reply_to,
                properties=pika.BasicProperties(
                    correlation_id = props.correlation_id
                ),
                body=self._encode_json(result)
            )

        self.channel.basic_ack(delivery_tag=method.delivery_tag)

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

    def emit_signal(self, signal_name, topic, **kwargs):
        print "Emitting signal!!!! with: {0}".format(kwargs)
        logger.warn("Emitting signal: {0}.{1}".format(topic, signal_name))
        self.channel.basic_publish(
            self.exchange,
            '{0}.{1}'.format(topic, signal_name),
            self._encode_json(kwargs, signal=True),
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

        routing_key = '{0}.{1}'.format(self.topic, method_name)
        logger.warn('RMQI subscribing to: {0}'.format(routing_key))

        # add this this callback
        self.signal_callbacks[routing_key] = method
        self.channel.queue_bind( self.queue,
                                 self.exchange,
                                 routing_key=routing_key)

        
