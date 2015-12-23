#!/usr/bin/env python

from __future__ import print_function
import logging
import logging.handlers
import time
import signal
import sys
import argparse
import datetime
import csv
import os
from cStringIO import StringIO
try:
    import simplejson as json
except:
    import json
    
import kafka as kafka_python
import pykafka
import threading

import flow_event_processor

logger_file = "/var/log/cloudsight/notification_processor.log"
PROCESSOR_GROUP = "notification_processor"

logger     = None

class KafkaInterface(object):
    def __init__(self, kafka_url, logger, notify_topic):

        '''
        XXX autocreate topic doesn't work in pykafka, so let's use kafka-python
        to create one.
        '''
        print('notification_topic'.format(notify_topic))

        try_num = 1
        while True:
            try:
                kafka_python_client = kafka_python.KafkaClient(kafka_url)
                kafka_python_client.ensure_topic_exists(notify_topic)
                break
            except UnknownError, e:
                logger.info('try_num={}, error connecting to {} , reason={}'.format(try_num, kafka_url, str(e)))
                time.sleep(60)
                try_num = try_num + 1

        self.logger = logger
        kafka = pykafka.KafkaClient(hosts=kafka_url)
        self.receive_topic_object = kafka.topics[notify_topic]

        # XXX replace the port in the broker url. This should be passed.
        zk_url = kafka_url.split(":")[0] + ":2181"
        self.consumer = self.receive_topic_object.get_balanced_consumer(
                                 reset_offset_on_start=True,
                                 fetch_message_max_bytes=512*1024*1024,
                                 consumer_group=PROCESSOR_GROUP,
                                 auto_commit_enable=True,
                                 zookeeper_connect = zk_url)

    def next_frame(self):
        messages = [self.consumer.consume() for i in xrange(1)]
        for message in messages:
            if message is not None:
                yield message.value

def sigterm_handler(signum=None, frame=None):
    print ('Received SIGTERM signal. Goodbye!', file=sys.stderr)
    sys.exit(0)
signal.signal(signal.SIGTERM, sigterm_handler)

class NotificationListener:

    def __init__(self, args, logger):
        self.flow_event_processor = flow_event_processor.FlowEventProcessor(logger, moving_window_size=args.window_size, es_host=args.elasticsearch_url)
        self.args = args
        self.logger = logger

    def print_event_log(self):
        self.logger.info ('sleeptime={}'.format(self.args.sleep_time))
        try:
            while True:
                self.flow_event_processor.print_event_log()
                time.sleep(self.args.sleep_time)
        except Exception, e:
            self.logger.error('----- daemon exited ')
            self.logger.exception(e)
            raise
        except SystemExit:
            self.logger.error('----- daemon exited ')
            self.logger.exception(e)
            raise
        
    def process_message(self):
        
        client = KafkaInterface(args.kafka_url, logger, args.notification_topic)
        t = threading.Thread(target=self.print_event_log)
        t.setDaemon(True)
        t.start()
        
        while True:
            processor_id = "{}-{}".format(PROCESSOR_GROUP, args.processor_id)
            try:
                for data in client.next_frame():
                    print (str(data))
                    self.logger.info(str(data))
                    self.flow_event_processor.add_notification(json.loads(data))
            except Exception, e:
                self.logger.exception(e)
    

if __name__ == '__main__':
    log_dir = os.path.dirname(logger_file)
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)
        os.chmod(log_dir,0755)

    format = '%(asctime)s %(levelname)s %(lineno)s %(funcName)s: %(message)s'
    logging.basicConfig(format=format, level=logging.INFO)
    
    logger = logging.getLogger(__name__)
    
    fh = logging.handlers.RotatingFileHandler(logger_file, maxBytes=2<<27, backupCount=4)
    formatter = logging.Formatter(format)
    fh.setFormatter(formatter)
    logger.addHandler(fh)
    logger.propagate = False

    try:
        parser = argparse.ArgumentParser(description="")
        parser.add_argument('--kafka-url',  type=str, required=True, help='kafka url: host:port')
        parser.add_argument('--notification-topic', type=str, required=True, help='topic to send process notification')
        parser.add_argument('--processor-id',  type=str, required=True, help='processor id')
        parser.add_argument('--elasticsearch-url',  type=str, default="http://localhost:9200", help='elasticsearch host')
        parser.add_argument('--sleep-time',  type=int, default=60, help='sleep time between completion checks')
        parser.add_argument('--window-size',  type=int, default=10, help='moving window size for computing processing averages')
        args = parser.parse_args()

        notification_listener = NotificationListener(args, logger)
        notification_listener.process_message()

    except Exception, e:
        print('Error: %s' % str(e))
        logger.exception(e) 


