#!/usr/bin/env python

'''
@author: Nilton Bila
@author  Sastry Duri, adopted for vulnerability annotator for kafka listening interface
(c) IBM Research 2015
'''

import logging
import time
import signal
import sys
import argparse
import datetime
import csv
from cStringIO import StringIO
try:
    import simplejson as json
except:
    import json
    
from kafka import SimpleProducer, KafkaClient, KafkaConsumer

import os
import re
import json
import pickle
import fileinput
import subprocess
import urllib
import urllib2
import calendar
import stat

from datetime import datetime

import os.path


logger_name = "notification_processsor"
logger_file = "notification_processsor.log"

class KafkaInterface(object):
    def __init__(self, kafka_url, logger, receive_topic, publish_topic, notify_topic):
        self.logger        = logger
        self.kafka_url     = kafka_url
        self.kafka         = KafkaClient(kafka_url)
        self.publish_topic = publish_topic
        self.receive_topic = receive_topic
        self.notify_topic = notify_topic
        
        self.kafka.ensure_topic_exists(receive_topic)
        #self.kafka.ensure_topic_exists(publish_topic)
        #self.kafka.ensure_topic_exists(self.notify_topic)
    
    def next_frame(self):
        consumer = KafkaConsumer(self.receive_topic, 
                                 group_id="notification_processor",
                                 metadata_broker_list=[self.kafka_url],
                                 fetch_message_max_bytes=512*1024*1024
                                 )
        for message in consumer:
            yield message.value
    
    def _publish(self, topic, data):
        producer = SimpleProducer(self.kafka)
        ret = producer.send_messages(topic, data)
        producer.stop()
        if ret:
            self.logger.debug("Published offset %s: %s" % (ret[0].offset, ret[0].error))

    def publish(self, data):
        self._publish(self.publish_topic, data)

    def notify(self, data):
        self._publish(self.notify_topic, data)


def sigterm_handler(signum=None, frame=None):
    print 'Received SIGTERM signal. Goodbye!'
    sys.exit(0)
signal.signal(signal.SIGTERM, sigterm_handler)
   
def write_event(line):
    if not ('processor') in line:
        return

    #if ('"crawler"') in line:
    #    line = line.replace(',"timestamp_ms"', '","timestamp_ms"', 1)
    #    line = line.replace('"timestamp":', '"timestamp":"', 1)

    data_json = {}
    try:
        data_json = json.loads(line)
    except Exception as err:
        print err 
        print line
        pass

    if (data_json == {}):
        return   
            
    namespace = data_json["namespace"]
    namespace = namespace.replace("/", "__", 10)
    #tmp = namespace.split("/")
    #image_name = tmp[0]
    #container_id = tmp[1]

    #namespace = image_name + "." + container_id
    fp = open("timeline/" + namespace, "a")
    fp.write(line + "\n")
    fp.close()

    file_path = "timeline/namespace.progress"
    if os.path.exists(file_path):

        with open (file_path, "r") as myfile:
            data=myfile.read()

        if not (namespace) in data:
            fp = open(file_path, "a")
            fp.write(namespace+"\n")
            fp.close()
    else:
        fp = open(file_path, "a")
        fp.write(namespace+"\n")
        fp.close()

 
def process_message(kafka_url, logger, receive_topic):
    
    client = KafkaInterface(kafka_url=kafka_url, logger=logger, receive_topic=receive_topic, publish_topic="", notify_topic="")
    
    while True:
        try:
            for data in client.next_frame():
#                json_data = json.loads(data);
#                print json_data["processor"]
                write_event(data)
                print data

        except Exception, e:
            logger.exception(e)
            logger.error("Uncaught exception: %s" % e)


if __name__ == '__main__':
    format = '%(asctime)s %(levelname)s %(lineno)s %(funcName)s: %(message)s'
    logging.basicConfig(filename=logger_file, filemode='w', format=format, level=logging.INFO)
    
    logger = logging.getLogger(logger_name)
    
    sh = logging.StreamHandler(sys.stdout)
    formatter = logging.Formatter(format)
    sh.setFormatter(formatter)
    logger.addHandler(sh)

    try:
        parser = argparse.ArgumentParser(description="")
        parser.add_argument('--kafka-url',  type=str, required=True, help='kafka url: host:port')
        parser.add_argument('--receive-topic', type=str, required=True, help='receive-topic')
        args = parser.parse_args()

        process_message(args.kafka_url, logger, args.receive_topic)
    except Exception, e:
        print('Error: %s' % str(e))
        logger.exception(e) 


