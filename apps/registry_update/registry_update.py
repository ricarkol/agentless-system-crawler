#!/usr/bin/env python

'''
@author: Nilton Bila
(c) IBM Research 2015
'''

import logging
import logging.handlers
import flask
from flask import abort
import argparse
import uuid
from functools import wraps
import errno
import signal
import os
import datetime
import time
import sys
import pykafka
import kafka as kafka_python
try:
    import simplejson as json
except:
    import json

app                 = flask.Flask('registry-update')

log_file            = '/var/log/cloudsight/registry-update-requests.log'
processor_group     = 'registry-update'
kafka_service       = None
updates_topic       = None
notifications_topic = None
instance_id         = 'unknown'
max_kafka_retries   = 600

class NullHandler(logging.Handler):
    def emit(self, record):
        pass


class TimeoutError(Exception):
    pass

class KafkaError(Exception):
    pass

def timeout(seconds=5, msg=os.strerror(errno.ETIMEDOUT)):
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

def notify(kafka_service, notifications_topic, uuid, event="start", processor="unknown", 
           instance_id="unknown", text="normal operation"):
    
    timestamp                 = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    timestamp_ms              = int(time.time() * 1e3)
    
    message                       = {}
    message["status"]             = event
    message["timestamp"]          = timestamp
    message["timestamp_ms"]       = timestamp_ms
    message["uuid"]               = uuid
    message["processor"]          = processor
    message["instance-id"]        = instance_id
    message["text"]               = text
    
    try: 
        post_to_kafka(kafka_service, notifications_topic, message)
    except KafkaError, e:
        app.logger.error(str(e))
        
#@timeout(10)
def send_message(producer, msg):
    producer.produce([msg])

def post_to_kafka(kafka_service, kafka_topic, message):
    msg = json.dumps(message)
    message_posted = False

    for i in range(max_kafka_retries):
        try:
            kafka_python_client = kafka_python.KafkaClient(kafka_service)
            kafka_python_client.ensure_topic_exists(kafka_topic)
            kafka_python_client.close()

            kafka = pykafka.KafkaClient(hosts=kafka_service)
            publish_topic_object = kafka.topics[kafka_topic]
            producer = publish_topic_object.get_producer()

            send_message(producer, msg)

            app.logger.debug('Published to kafka: %s' % msg)
            message_posted = True
            break
        except TimeoutError, e:
            app.logger.warn('Kafka send timed out: %s, %s' % (kafka_service, str(message)))
        except Exception, e:
            app.logger.warn('Kafka send failed: %s, %s (error=%s)' % (kafka_service, msg, str(e)))
        time.sleep(1)

    if not message_posted:
        raise KafkaError('Failed to publish message to Kafka after %d retries: %s' % (max_kafka_retries, msg))
        

@app.before_first_request
def initialize():
    format = '%(asctime)s %(name)-12s: %(levelname)-8s LINE=%(lineno)s %(message)s'
    app.logger.setLevel(logging.DEBUG)

    h = NullHandler()
    logging.getLogger("kafka").addHandler(h)

    fh = logging.handlers.RotatingFileHandler(log_file, maxBytes = 33554432, backupCount = 10)
    fh.setFormatter(logging.Formatter(format))
    fh.setLevel(logging.INFO)
    app.logger.addHandler(fh)
    
@app.route('/', methods=['GET'])
def welcome():
   return '''CloudSight Registry Update Service:
             /registry/update
             '''

@app.route('/registry/update', methods=['POST'])
def update():
    request_uuid = str(uuid.uuid1())
    app.logger.info('Received request uuid: %s' % request_uuid)
    notify(kafka_service, notifications_topic, request_uuid, event="start",
           processor=processor_group, instance_id=instance_id)
    
    try:
        image_info = flask.request.get_json(force=True)
    except Exception, e:
        app.logger.error(e)
        abort(400)
    
    image_info['uuid'] = request_uuid
    try:
        image_info['namespace'] = '%s:%s' % (image_info['repository'], image_info['tag'])
    except KeyError, e:
        if 'namespace' not in image_info:
            app.logger.error('Bad data: field %s missing from image info: %s' % (str(e), str(image_info)))
            abort(400)
    try:
        post_to_kafka(kafka_service, updates_topic, image_info)

        app.logger.info('Published request %s to topic %s: %s' % (request_uuid, updates_topic, json.dumps(image_info, sort_keys=True)))
        
        notify(kafka_service, notifications_topic, request_uuid, event="completed",
               processor=processor_group, instance_id=instance_id)
    except (KafkaError, Exception), e:
        app.logger.error('Kafka send failure: %s' % str(e))
        notify(kafka_service, notifications_topic, request_uuid, event="error",
               processor=processor_group, instance_id=instance_id)
        abort(500)
        
    return 'Image update published to Vulnerability Advisor Service'
    
if __name__ == "__main__":
    log_dir = os.path.dirname(log_file)
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)
        os.chmod(log_dir,0755)

    try:
        parser = argparse.ArgumentParser(description="registry update service")
        parser.add_argument('--listen-port', type=int, required=False, default=8000, help='listen port')
        parser.add_argument('--kafka-service', type=str, required=True, default=None, help='kafka service host e.g. kafka-cs.sl.cloud9.ibm.com:9092')
        parser.add_argument('--kafka-updates-topic', type=str, required=False, default='registry-updates', help='kafka registry updates topic')
        parser.add_argument('--kafka-notifications-topic', type=str, required=False, default='notification', help='kafka registry updates topic')
        parser.add_argument('--instance-id', type=str, required=False, default='unknown', help='registry-update instance-id')
        args = parser.parse_args()
    
        listen_port  = args.listen_port
        kafka_service = args.kafka_service
        updates_topic = args.kafka_updates_topic
        notifications_topic = args.kafka_notifications_topic
        instance_id = args.instance_id
        
        print >>sys.stderr, "starting registry-update service"
        app.run(host='0.0.0.0', port=listen_port, threaded=True)
    except Exception, e:
        print('Error: %s' % str(e))
