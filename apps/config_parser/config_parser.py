#!/usr/bin/env python

'''
@author: Nilton Bila
(c) IBM Research 2015
'''

"""
This app parses system and application configuration file content emitted 
as 'config' features to the CloudSight broker's 'Config' channel, extracts 
the configuration parameters, and re-emits them to three channels:
'User' - for system user account info
'Group' - for system group info 
'ConfigParam' - for all other configuration parameters 
"""


import augeas_parser
import logging
import logging.handlers
import time
import sys
import argparse
import csv
import os
from functools import wraps
import errno
import signal
import datetime
import pykafka.cluster
from retry import retry
from pykafka.exceptions import KafkaException


try:
    from cStringIO import StringIO
except:
    from StringIO import StringIO

import json

import kafka as kafka_python
import pykafka

allowed_messages = ['ConfigParam', 'User', 'Group']
feature2channel     = {
                   'configparam': 'ConfigParam',
                   'user':         'User',
                   'group':        'Group'
                   }

logger                = None
log_file              = '/var/log/cloudsight/config-parser.log'
obj_factory           = None
processor_group       = "config-parser"
max_kafka_retries     = 600
max_read_message_retries = 60
kafka_reconnect_after = 60
kafka_send_timeout    = 60
        

class TimeoutError(Exception):
    pass

class KafkaError(Exception):
    pass

class TestException(KafkaException):
    pass

def timeout(seconds=60, msg=os.strerror(errno.ETIMEDOUT)):
    def decorator(func):
        def timeout_handler(sig, frame):
            raise TimeoutError(msg)

        def wrapper(*args, **kwargs):
            signal.signal(signal.SIGALRM, timeout_handler)
            signal.alarm(seconds)
            try:
                ret = func(*args, **kwargs)
            finally:
                signal.alarm(0)
            return ret

        return wraps(func)(wrapper)

    return decorator

class KafkaInterface(object):
    def __init__(self, kafka_url, kafka_zookeeper_port, logger, receive_topic, publish_topic, notify_topic, test=False):
        self.logger        = logger
        self.kafka_url     = kafka_url
        self.kafka_zookeeper_port = kafka_zookeeper_port
        self.receive_topic = receive_topic 
        self.publish_topic = publish_topic
        self.notify_topic  = notify_topic
        self.test = test
        self.consumer_test_complete = False

        # Monkey patching the logger file of cluster, so that we get the output to our logs
        pykafka.cluster.log = logger
        self.connect_to_kafka()

    def connect_to_kafka(self):
        '''
        XXX autocreate topic doesn't work in pykafka, so let's use kafka-python
        to create one.
        '''
        kafka_python_client = kafka_python.SimpleClient(self.kafka_url)
        kafka_python_client.ensure_topic_exists(self.receive_topic)
        kafka_python_client.ensure_topic_exists(self.publish_topic)
        kafka_python_client.ensure_topic_exists(self.notify_topic)

        kafka = pykafka.KafkaClient(hosts=self.kafka_url)
        self.receive_topic_object = kafka.topics[self.receive_topic]
        self.publish_topic_object = kafka.topics[self.publish_topic]
        self.notify_topic_object = kafka.topics[self.notify_topic]

        # XXX replace the port in the broker url. This should be passed.
        if self.kafka_url.find(':') != -1:
            zk_url = self.kafka_url.rsplit(":", 1)[0] + ":%s" % self.kafka_zookeeper_port
        else:
            zk_url = self.kafka_url + ":%s" % self.kafka_zookeeper_port
        self.consumer = self.receive_topic_object.get_balanced_consumer(
                                 reset_offset_on_start=True,
                                 fetch_message_max_bytes=512*1024*1024,
                                 consumer_group=processor_group,
                                 auto_commit_enable=True,
                                 zookeeper_connect = zk_url)
        self.producer = self.publish_topic_object.get_sync_producer()
        self.notifier = self.notify_topic_object.get_sync_producer()
        self.logger.info('Connected to kafka broker at %s' % self.kafka_url)

    def stop_kafka_clients(self):
        if hasattr(self, 'consumer'):
            self.consumer.stop()
        if hasattr(self, 'producer'):
            self.producer.stop()
        if hasattr(self, 'notifier'):
            self.notifier.stop()
        self.logger.info('Stopped kafka client on %s' % self.kafka_url)

    def consumer_reconnect_process(self):
        if self.consumer._running is True:
            self.logger.info("Consumer running, stopping Kafka Clients")
            self.stop_kafka_clients()
            time.sleep(1)
        self.connect_to_kafka()
        time.sleep(1)
        self.logger.error("Kafka restart attempted {}".format(self.kafka_url))
        raise KafkaException("Kafka restart attempted {}".format(self.kafka_url))


    @retry(KafkaException, tries=max_read_message_retries, delay=0.1, backoff=0.5, max_delay=2)
    def next_frame(self):
        message = None
        try:
            #### TEST BLOCK ####
            if self.test and not self.consumer_test_complete:
                self.logger.info("TEST --------- Testing that consumer is running")

                assert self.consumer._running is True
                self.logger.info("TEST --------- Consumer is running, skipping attempt to consumer, will restart kafka connection")
                self.consumer_test_complete = True
                raise TestException("Test")
            #### TEST BLOCK END ####
            message = self.consumer.consume()
        except KafkaException as e:
            self.logger.error('Failed to get new message from kafka: %s' % repr(e))
            self.consumer_reconnect_process()


        # Could log the config_parser instance ID as well if passed into KafkaInterface.__init__
        # self.logger.info('CP Partition %s offset %s' % (message.partition_id, message.offset))
        if message is not None:
            yield message.value
        
    @timeout(kafka_send_timeout)
    def send_message(self, producer, msg):
        producer.produce(msg)

    def post_to_kafka(self, producer, msg, request_id):
        message_posted = False
        for i in range(max_kafka_retries):
            try:
                self.send_message(producer, msg)
                message_posted = True
                break
            except TimeoutError as e:
                self.logger.warn('%s: Kafka send timed out: %s (error=%s)' % (request_id, self.kafka_url, repr(e)))
            except Exception as e:
                self.logger.warn('%s: Kafka send failed: %s (error=%s)' % (request_id, self.kafka_url, repr(e)))

            time.sleep(1)

            if i > kafka_reconnect_after:
                try:
                     self.stop_kafka_clients()
                     self.connect_to_kafka()
                except Exception as e:
                     self.logger.error('%s: Failed to reconnect to kafka at %s (error=%s)' % (request_id, self.kafka_url, repr(e)))

        if not message_posted:
            raise KafkaError('Failed to publish message to Kafka after %d retries: %s' % (max_kafka_retries, msg))

    def publish(self, data, metadata, request_id):
        stream = StringIO()
        csv.field_size_limit(sys.maxsize) # required to handle large value strings
        csv_writer = csv.writer(stream, delimiter='\t', quotechar="'")
        
        metadata['features'] = 'user,group,configparam'
        csv_writer.writerow(('metadata', json.dumps('metadata'), json.dumps(metadata)))
        
        for ftype, fkey, fvalue in data:
            csv_writer.writerow((ftype, json.dumps(fkey), json.dumps(fvalue)))
            
        ret = None
        msg = stream.getvalue()

        self.post_to_kafka(self.producer, msg, request_id)

        stream.close()
        

    def notify(self, request_id, metadata, event="start", processor="unknown", instance_id="unknown", text="normal operation"):
    
        timestamp                 = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        timestamp_ms              = int(time.time() * 1e3)
    
        message                       = {}
        message["status"]             = event
        message["timestamp"]          = timestamp
        message["timestamp_ms"]       = timestamp_ms
        message["uuid"]               = "unknown"
        message["processor"]          = processor
        message["instance-id"]        = instance_id
        message["text"]               = text
        try:
            message["namespace"]      = metadata['namespace']
            message["crawl_timestamp"]= metadata['timestamp']
            message["uuid"]           = metadata['uuid']
        except Exception as e:
            self.logger.warn('%s: Missing metadata in kafka notification: %s' % \
                             (request_id, repr(e)))

        msg = json.dumps(message)
        self.post_to_kafka(self.notifier, msg, request_id)
        self.logger.info(msg)
            
        
def sigterm_handler(signum=None, frame=None):
    print 'Received SIGTERM signal. Goodbye!'
    sys.exit(0)
signal.signal(signal.SIGTERM, sigterm_handler)
    
def config_parser(kafka_url, kafka_zookeeper_port, logger, receive_topic, 
                  publish_topic, notification_topic, 
                  known_config_files, suppress_comment, instance_id, test):
    parser = augeas_parser.AugeasParser(logger, suppress_comments)
  
    client = None 

    while True:
        try:
            client = KafkaInterface(kafka_url, kafka_zookeeper_port, logger, receive_topic, 
                                    publish_topic, notification_topic, test)
            break
        except Exception as e:
            logger.error('Failed to establish connection to kafka broker at %s: %s' % \
                        (kafka_url, repr(e)))
            time.sleep(5)
    if not client:
        return
    
    while True:
        try:
            for data in client.next_frame():
                            
                frame = []
                annotations = []
                stream = StringIO(data)
                csv.field_size_limit(sys.maxsize) # required to handle large value strings
                csv_reader = csv.reader(stream, delimiter='\t', quotechar="'")
                metadata     = None
                namespace    = 'unknown'
                request_id = 'unknown'
                for ftype, fkey, fvalue in csv_reader:
                    frame.append((ftype, json.loads(fkey), json.loads(fvalue)))
                    if not metadata and ftype == 'metadata':
                        try:
                            metadata = json.loads(fvalue)
                            namespace = metadata['namespace']
                            request_id = metadata['uuid']
                        except (ValueError, KeyError) as e:
                            logger.error("%s: Bad data in frame: %s, %s" % \
                                        (request_id, fkey, fvalue))
                stream.close()
                
                if not metadata or not metadata['features'] or \
                   'configparam' in metadata['features'].split(','):
                    logger.info('%s: Non config frame will not be processed' % \
                                (request_id))
                    continue

                logger.info("%s: Processing request %s" % \
                            (request_id, namespace))
        
                try:
                    client.notify(request_id=request_id, 
                                  metadata=metadata, 
                                  event="start",
                                  processor=processor_group, 
                                  instance_id=instance_id)
                except KafkaError as e:
                    logger.error('%s: Failed to send notification to kafka for namespace %s: %s' % \
                                  (request_id, namespace, repr(e)))
                            
                try:
                    annotations = parser.parse_update(frame, known_config_files, request_id, namespace)
                except Exception as e:
                    logger.error("%s: Failed to parse frame for namespace %s: %s" % \
                                    (request_id, namespace, repr(e)))
                    try:
                        client.notify(request_id=request_id, 
                                      metadata=metadata, 
                                      event="error",
                                      processor=processor_group, 
                                      instance_id=instance_id, text=repr(e))
                    except KafkaError as e:
                        logger.error('%s: Filed to send notification to kafka for namespace %s, %s' % \
                                     (request_id, namespace, repr(e)))
                    continue
               
                annotations.append(('configparam', 
                                    'configparam_annotated', 
                                    {'parameter': 'configparam_annotated', 
                                     'value': 'true', 
                                     'file': '/virt/config-parser'}
                                    ))
            
                if len(annotations):
                    logger.info("%s: Parsed %d annotations for %s" % \
                                (request_id, (len(annotations) - 1), namespace))
                    
                    try:
                        client.publish(annotations, metadata, request_id)
                    except Exception as e:
                        logger.error('%s: Failed to send annotations to kafka for %s, %s' % \
                                     (request_id, namespace, repr(e)))
                        try:
                            client.notify(request_id=request_id, 
                                          metadata=metadata, 
                                          event="error", 
                                          processor=processor_group, 
                                          instance_id=instance_id, text=repr(e))
                        except KafkaError as e:
                            logger.error('%s: Failed to send notification to kafka for %s: %s' % \
                                         (request_id, namespace, repr(e)))
                        continue

                else:
                    logger.info("%s: No annotations found in frame for %s" % \
                                (request_id, namespace))
                    
                try:
                    client.notify(request_id=request_id,
                                  metadata=metadata, 
                                  event="completed", 
                                  processor=processor_group, 
                                  instance_id=instance_id, 
                                  text="produced %d annotations" % (len(annotations) - 1))
                except KafkaError as e:
                    logger.error('%s: Failed to send notification to kafka for %s: %s' % \
                                  (request_id, namespace, repr(e)))
                            
                logger.info("%s: Finished processing request %s" % (request_id, namespace))
        except Exception as e:
            logger.error("Uncaught exception: %s" % e)
            raise


if __name__ == '__main__':
    log_dir = os.path.dirname(log_file)
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)
        os.chmod(log_dir,0755)

    format = '%(asctime)s %(levelname)s %(lineno)s %(funcName)s: %(message)s'
    logging.basicConfig(format=format, level=logging.INFO)
    
    logger = logging.getLogger(__name__)
    
    fh = logging.handlers.RotatingFileHandler(log_file, maxBytes=2<<27, backupCount=4)
    formatter = logging.Formatter(format)
    fh.setFormatter(formatter)
    logger.addHandler(fh)
    logger.propagate = False
    logger.info("===================================================")
    logger.info("STARTING NEW CONFIG PARSER INSTANCE")
    logger.info("===================================================")

    try:
        parser = argparse.ArgumentParser(description="")
        parser.add_argument('--kafka-url',  type=str, default=None, required=True, help='kafka-url')
        parser.add_argument('--kafka-zookeeper-port',  type=str, required=True, help='kafka zookeeper port')
        parser.add_argument('--receive-topic', type=str, default='config', help='receive-topic')
        parser.add_argument('--publish-topic', type=str, default='config', help='publish-topic')
        parser.add_argument('--notification-topic', type=str, default='notification', help='kafka notifications-topic')
        parser.add_argument('--suppress-comments', type=str, default='true', help='suppress comments=true|false')
        parser.add_argument('--instance-id', type=str, default='unknown', help='config-parser instance-id')
        parser.add_argument('--test', action='store_true')
        parser.add_argument('--known-config-files', type=str, default='[]', help='list of config files to parse')
        args = parser.parse_args()
    
        suppress_comments = bool(args.suppress_comments)
        known_config_files = json.loads(args.known_config_files)
        config_parser(args.kafka_url, args.kafka_zookeeper_port, logger, args.receive_topic, 
                      args.publish_topic, args.notification_topic, 
                      known_config_files, suppress_comments, args.instance_id, args.test)
    except Exception as e:
        print('Error: %s' % repr(e))
        logger.exception(e)



