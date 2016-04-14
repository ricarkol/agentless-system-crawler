#!/usr/bin/env python

'''
@author: Nilton Bila
(c) IBM Research 2015
'''
import datetime

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
import signal
try:
    from cStringIO import StringIO
except:
    from StringIO import StringIO

import json
from va_python_base.KafkaInterface import KafkaInterface
from va_python_base.KafkaInterface import KafkaError

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


def sigterm_handler(signum=None, frame=None):
    print 'Received SIGTERM signal. Goodbye!'
    sys.exit(0)
signal.signal(signal.SIGTERM, sigterm_handler)

def create_notification_message(request_id, metadata, event="start", processor="unknown", instance_id="unknown", text="normal operation"):
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
        logger.warn('%s: Missing metadata in kafka notification: %s' % \
                         (request_id, repr(e)))
    return message
    
def config_parser(kafka_url, kafka_zookeeper_port, logger, receive_topic, 
                  publish_topic, notification_topic, 
                  known_config_files, suppress_comment, instance_id):
    parser = augeas_parser.AugeasParser(logger, suppress_comments)
  
    client = None 

    while True:
        try:
            client = KafkaInterface(kafka_url, kafka_zookeeper_port, logger, receive_topic, publish_topic, notification_topic)
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
        
                message = create_notification_message(request_id, metadata, "start", processor_group, instance_id, "normal operation")
                msg = json.dumps(message)
                logger.info(msg)
                client.notify(msg, request_id,namespace)

                            
                try:
                    annotations = parser.parse_update(frame, known_config_files, request_id, namespace)
                except Exception as e:
                    logger.error("%s: Failed to parse frame for namespace %s: %s" % \
                                    (request_id, namespace, repr(e)))
                    message = create_notification_message(request_id, metadata, "error", processor_group, instance_id, repr(e))
                    msg = json.dumps(message)
                    logger.info(msg)
                    client.notify(msg, request_id,namespace)

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
                    
                    stream = StringIO()
                    csv.field_size_limit(sys.maxsize) # required to handle large value strings
                    csv_writer = csv.writer(stream, delimiter='\t', quotechar="'")

                    metadata['features'] = 'user,group,configparam'
                    csv_writer.writerow(('metadata', json.dumps('metadata'), json.dumps(metadata)))

                    for ftype, fkey, fvalue in data:
                        csv_writer.writerow((ftype, json.dumps(fkey), json.dumps(fvalue)))

                    msg = stream.getvalue()
                    client.publish(msg,request_id,namespace)

                else:
                    logger.info("%s: No annotations found in frame for %s" % \
                                (request_id, namespace))
                    
                message = create_notification_message(request_id, metadata, "completed", processor_group, instance_id, "produced %d annotations" % (len(annotations) - 1))
                msg = json.dumps(message)
                logger.info(msg)
                client.notify(msg, request_id,namespace)
                            
                logger.info("%s: Finished processing request %s" % (request_id, namespace))
        except Exception as e:
            logger.error("Exiting with exception: %s" % e)
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
        parser.add_argument('--known-config-files', type=str, default='[]', help='list of config files to parse')
        args = parser.parse_args()
    
        suppress_comments = bool(args.suppress_comments)
        known_config_files = json.loads(args.known_config_files)
        config_parser(args.kafka_url, args.kafka_zookeeper_port, logger, args.receive_topic, 
                      args.publish_topic, args.notification_topic, 
                      known_config_files, suppress_comments, args.instance_id)
    except Exception as e:
        print('Error: %s' % repr(e))
        logger.exception(e)
        raise 



