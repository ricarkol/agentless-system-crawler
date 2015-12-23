#!/usr/bin/env python

'''
@author: Nilton Bila
@author: Sastry Duri, adopted for vulnerability annotator for kafka listening interface
@author: Byungchul Tak, adapted this to compliance.
@author: Praveen Jayachandran, adapted this to password annotator.
(c) IBM Research 2015
'''
import os
import re
import pickle
import fileinput
import subprocess
import calendar
import ConfigParser
import stat
from collections import defaultdict
#from kafka import KafkaClient, SimpleProducer, KeyedProducer
import uuid

import logging
import logging.handlers
import time
import signal
import sys
import argparse
import datetime
import csv
import pdb
import tempfile
from cStringIO import StringIO

try:
    import simplejson as json
except:
    import json
    
from timeout import timeout
import kafka as kafka_python
import pykafka

from multiprocessing import Pool

PROCESSOR_GROUP = "password_annotator"
COMPLIANCE_ID = "Linux.20-"

class KafkaInterface(object):
    def __init__(self, kafka_url, receive_topic):

        '''
        XXX autocreate topic doesn't work in pykafka, so let's use kafka-python
        to create one.
        '''
        try_num = 1
        while True:
            try:
                kafka_python_client = kafka_python.KafkaClient(kafka_url)
                kafka_python_client.ensure_topic_exists(receive_topic)
                break
            except UnknownError, e:
                time.sleep(60)
                try_num = try_num + 1

        self.kafka_url = kafka_url
        kafka = pykafka.KafkaClient(hosts=kafka_url)
        self.receive_topic_object = kafka.topics[receive_topic]

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
    print 'Received SIGTERM signal. Goodbye!'
    sys.exit(0)
signal.signal(signal.SIGTERM, sigterm_handler)

def process_message(kafka_url, receive_topic):
    
    # Initialize the kafka object
    client = KafkaInterface(kafka_url, receive_topic)
    
    while True:
        try:
            # Read one frame at a time
            for data in client.next_frame():
                data = data.strip('\n')
                print data
#                json_str = json.loads(data)
#                if COMPLIANCE_ID in json_str['compliance_id']:
#                print str(json_str)
        except Exception, e:
            continue


if __name__ == '__main__':
    try:
        parser = argparse.ArgumentParser(description="")
        parser.add_argument('--kafka-url',  type=str, required=True, help='kafka url: host:port')
        parser.add_argument('--receive-topic', type=str, required=True, help='receive-topic')

        args = parser.parse_args()
        process_message(args.kafka_url, args.receive_topic)
    except Exception, e:
        print('Error: %s' % str(e))
