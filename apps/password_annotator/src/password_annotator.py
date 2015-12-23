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
    
import timeout
import kafka as kafka_python
import pykafka

from multiprocessing import Pool

logger_file = "/var/log/cloudsight/password-annotator.log"
PROCESSOR_GROUP = "password_annotator"
COMPLIANCE_ID_PW_ENABLED = "Linux.20-0-b"
COMPLIANCE_ID_PW_STRENGTH = "Linux.20-0-c"
SSHD_CONFIG_FILES = ['/etc/ssh/sshd_config']

class KafkaInterface(object):
    def __init__(self, kafka_url, logger, receive_topic, publish_topic, notify_topic):

        '''
        XXX autocreate topic doesn't work in pykafka, so let's use kafka-python
        to create one.
        '''
        try_num = 1
        while True:
            try:
                kafka_python_client = kafka_python.KafkaClient(kafka_url)
                kafka_python_client.ensure_topic_exists(receive_topic)
                kafka_python_client.ensure_topic_exists(publish_topic)
                kafka_python_client.ensure_topic_exists(notify_topic)
                break
            except pykafka.exceptions.UnknownError, e:
                logger.info('try_num={}, error connecting to {} , reason={}'.format(try_num, kafka_url, str(e)))
                time.sleep(60)
                try_num = try_num + 1

        self.logger = logger
        self.kafka_url = kafka_url
        kafka = pykafka.KafkaClient(hosts=kafka_url)
        self.receive_topic_object = kafka.topics[receive_topic]
        self.publish_topic_object = kafka.topics[publish_topic]
        self.notify_topic_object = kafka.topics[notify_topic]

        # XXX replace the port in the broker url. This should be passed.
        zk_url = kafka_url.split(":")[0] + ":2181"
        self.consumer = self.receive_topic_object.get_balanced_consumer(
                                 reset_offset_on_start=True,
                                 fetch_message_max_bytes=512*1024*1024,
                                 consumer_group=PROCESSOR_GROUP,
                                 auto_commit_enable=True,
                                 zookeeper_connect = zk_url)
        self.producer = self.publish_topic_object.get_producer()
        self.notifier = self.notify_topic_object.get_producer()

    def next_frame(self):
        messages = [self.consumer.consume() for i in xrange(1)]
        for message in messages:
            if message is not None:
                yield message.value

    @timeout.timeout(30)
    def publish(self, data, uuid):
        trial_num=0
        while True:
            try:
                self.producer.produce([data])
                break
            except timeout.TimeoutError, e:
                self.logger.warn('Could not send data to {0}, uuid={1}, trial={2} reason={3}, data={4}'.format(self.kafka_url, uuid, trial_num, e, data))
                trial_num = trial_num + 1

    @timeout.timeout(30)
    def notify(self, data, uuid):
        trial_num=0
        while True:
            try:
                self.notifier.produce([data])
                break
            except timeout.TimeoutError, e:
                self.logger.warn('Could not send data to {0}, uuid={1}, trial={2} reason={3}, data={4}'.format(self.kafka_url, uuid, trial_num, e, data))
                trial_num = trial_num + 1


def sigterm_handler(signum=None, frame=None):
    print 'Received SIGTERM signal. Goodbye!'
    sys.exit(0)
signal.signal(signal.SIGTERM, sigterm_handler)

def check_sshd_password_enabled(sshd_config, namespace, crawled_time, input_reqid):
    report = {
             "compliance_id": COMPLIANCE_ID_PW_ENABLED,
             "namespace": namespace,
             "crawled_time": crawled_time,
             "compliance_check_time": datetime.datetime.utcnow().isoformat()+'Z',
             "input_reqid": input_reqid,
             "execution_status": "Success",
             "description": "SSHD password enabled check",
             "compliant": "true",
             "reason": "Password authentication not enabled"
             }
  
    if len(sshd_config.keys()) == 0:
        report["compliant"] = "true"
        report["reason"] = "No sshd_config file was found"
    elif 'PasswordAuthentication' not in sshd_config:
        report["compliant"] = "false"
        report["reason"] = "PasswordAuthentication not found in sshd_config. Default value is yes."
    elif "ChallengeResponseAuthentication" not in sshd_config:
        report["compliant"] = "false"
        report["reason"] = "ChallengeResponseAuthentication not found in sshd_config. Default value is yes."
    elif "value" in sshd_config["PasswordAuthentication"] and \
        sshd_config["PasswordAuthentication"]["value"] == "yes":
        report["compliant"] = "false"
        report["reason"] = "PasswordAuthentication is set to 'yes' in sshd_config."
    elif "value" in sshd_config["ChallengeResponseAuthentication"] and \
        sshd_config["ChallengeResponseAuthentication"]["value"] == "yes":
        report["compliant"] = "false"
        report["reason"] = "ChallengeResponseAuthentication is set to 'yes' in sshd_config."

    return report 



def process_message(kafka_url, logger, receive_topic, publish_topic, notification_topic, instance_id):
    
    # Initialize the kafka object
    client = KafkaInterface(kafka_url, logger, receive_topic, publish_topic, notification_topic)
    
    while True:
        try:
            # Read one frame at a time
            for data in client.next_frame():
                stream = StringIO(data)
                csv.field_size_limit(sys.maxsize) # required to handle large value strings
                csv_reader = csv.reader(stream, delimiter='\t', quotechar="'")
                metadata = None
                password_data = []
                sshd_config = dict()
                password_flag = False
                for ftype, fkey, fvalue in csv_reader:
                    #logger.info(ftype + "," + fkey + "," + fvalue)
                    fkey = json.loads(fkey)
                    fvalue = json.loads(fvalue)
                    # Collect password data frames
                    if ftype == 'configparam' and 'file' in fvalue:
                        if fvalue['file'] in ['/etc/shadow', '/etc/passwd'] and fkey.endswith('password'):
                            password_data.append(fvalue)
                        elif (fkey == 'user' or fkey == 'group') and 'password' in fvalue:
                            password_flag = True
                        elif fvalue['file'] in SSHD_CONFIG_FILES and 'parameter' in fvalue:
                            sshd_config[fvalue['parameter']] = fvalue
                    # Collect metadata frame
                    if not metadata and ftype == 'metadata':
                        metadata = fvalue
                stream.close()

                #print metadata
                #print password_data
                #logger.info(metadata)
                #logger.info(password_data)

                logger.info(metadata['uuid']+" NEW FRAME")
                log_message=""
                features = metadata.get('features',None)
                if features and 'configparam' in features:
                    log_message=log_message+" ,configparam:exists"
                else:
                    log_message=log_message+" ,configparam:nonexisting"
                logger.info(metadata['uuid']+" 00 "+log_message)

                # METADATA SAMPLE
                #{
                #    "compress": false,
                #    "container_image": "7bbe627dab2dfc2418c4a5c1ac7448dc308358fe4bee04737b6957cecd90c40c",
                #    "container_long_id": "1297d2946858a21276d1a2a4582110bcfa7d99656a051bf1db471f7237b9fd1d",
                #    "container_name": "8de9c596-fa6e-11e4-a978-0683fe7128d5",
                #    "features": "os,disk,file,package,config,dockerhistory,dockerps,dockerinspect",
                #    "namespace": "secreg2.sl.cloud9.ibm.com:5000/ubuntu-rkoller-15",
                #    "owner_namespace": "kollerr",
                #    "since": "EPOCH",
                #    "since_timestamp": 0,
                #    "system_type": "container",
                #    "timestamp": "2015-05-14T14:22:27-0500",
                #    "uuid": "8eda5cb8-fa6e-11e4-926e-0683fe7128d5"
                #}

                namespace = str(metadata['namespace']).strip()
                timestamp = str(metadata['timestamp']).strip()
                metadata_uuid = "unknown"
                if 'uuid' in metadata:
                    metadata_uuid = metadata['uuid']

                features = metadata.get('features',None)
                if not features or 'configparam' not in features:
                    # password annotator processes only configparser data
                    logger.info(metadata_uuid+" 01 Skipping non-configparam frame for "+namespace+" "+timestamp)
                    continue

                logger.info(metadata_uuid+" 02 NAMESPACE              :"+ namespace)
                logger.info(metadata_uuid+" 03 TIMESTAMP              :"+ timestamp)

                # Create the notification message
                notification_msg = { 
                    'processor': PROCESSOR_GROUP,
                    'instance-id': args.instance_id,
                    'status': 'start',
                    'namespace': namespace,
                    'timestamp': datetime.datetime.utcnow().isoformat()+'Z',
                    'timestamp_ms': int(time.time())*1000,
                    'uuid': metadata_uuid,
                    'text': 'Normal operation'
                }

                # Notify start
                msg = json.dumps(notification_msg)
                client.notify(msg,metadata_uuid)
                logger.info(msg)

                msg_buf = StringIO()
                msg_buf.write(json.dumps(metadata))
                msg_buf.write('\n')
                sshd_password_msg = check_sshd_password_enabled(
                                            sshd_config, 
                                            namespace, 
                                            timestamp, 
                                            metadata_uuid)
                msg_buf.write(json.dumps(sshd_password_msg))
                msg_buf.write('\n')
                logger.info(json.dumps(sshd_password_msg))
                #client.publish(json.dumps(sshd_password_msg), metadata_uuid)

                # Create the publish message
                publish_msg = {
                    'compliance_id' : COMPLIANCE_ID_PW_STRENGTH,
                    'namespace' : namespace,
                    'crawled_time' : timestamp,
                    'input_reqid' : metadata_uuid,
                    'description' : 'Weak password check'
                }     

                if password_flag:
                    # Passwords stored in plain text - non-compliant
                    # Send notify message
                    notification_msg['status'] = 'completed'
                    notification_msg['timestamp'] = datetime.datetime.utcnow().isoformat()+'Z'
                    notification_msg['timestamp_ms'] = int(time.time())*1000
                    notification_msg['text'] = 'Passwords found'

                    msg = json.dumps(notification_msg)
                    client.notify(msg,metadata_uuid)
                    logger.info(msg)

                    # Send publish message
                    publish_msg['compliance_check_time'] = datetime.datetime.utcnow().isoformat()+'Z'
                    publish_msg['execution_status'] = "Success"
                    publish_msg['compliant'] = "false"
                    publish_msg['reason'] = "Passwords stored in plain text"
                    msg_buf.write(json.dumps(publish_msg))
                    msg_buf.write('\n')
                    client.publish(msg_buf.getvalue(), metadata_uuid)
                    logger.info(json.dumps(publish_msg))
                  
                    continue

                # Check if some password data has been received
                if not password_data:
                    # Send notify message
                    notification_msg['status'] = 'completed'
                    notification_msg['timestamp'] = datetime.datetime.utcnow().isoformat()+'Z'
                    notification_msg['timestamp_ms'] = int(time.time())*1000
                    notification_msg['text'] = 'No passwords found'

                    msg = json.dumps(notification_msg)
                    client.notify(msg,metadata_uuid)
                    logger.info(msg)

                    # Send publish message
                    publish_msg['compliance_check_time'] = datetime.datetime.utcnow().isoformat()+'Z'
                    publish_msg['execution_status'] = "Success"
                    publish_msg['compliant'] = "true"
                    publish_msg['reason'] = "No passwords found"
                    msg_buf.write(json.dumps(publish_msg))
                    msg_buf.write('\n')
                    client.publish(msg_buf.getvalue(), metadata_uuid)
                    logger.info(json.dumps(publish_msg))
                  
                    continue
    
                # The main password checking
                process_error = 0
                good_count = 0
                bad_count = 0
                bad_users = ''
                for entry in password_data:
                    items = entry['parameter'].split('/')
                    username = items[0]
                    if items[1] == 'password':
                        # This is a password entry
                        password_value = entry['value']

                        if password_value == '*':
                            continue

                        # Write the password to a temporary file
                        tmpfile = tempfile.NamedTemporaryFile(mode='a', delete=False)
                        tmpfile.write(password_value)
                        tmpfile.close()

                        # Invoke John on this password
                        cmd = "john --single " + tmpfile.name
                        p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                        outdata = p.communicate()[0]
                        returncode = p.returncode

                        if returncode != 0:
                            process_error = 1
                            break

                        cmd = "john --wordlist=/usr/share/john/password.lst " + tmpfile.name
                        p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                        outdata = p.communicate()[0]
                        returncode = p.returncode

                        if returncode != 0:
                            process_error = 1
                            break

                        cmd = "john --show " + tmpfile.name
                        p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                        outdata = p.communicate()[0]
                        last_line = outdata.split('\n')[-2]

                        if last_line.startswith('0 password hashes cracked'):
                            good_count = good_count + 1
                        elif 'password hash' in last_line:
                            bad_count = bad_count + 1
                            if bad_users == '':
                                bad_users = username
                            else:
                                bad_users = bad_users + ',' + username
                        else:
                            process_error = 1
                            break

                        # Remove temporary file
                        os.unlink(tmpfile.name)

                if process_error == 1:                       
                    notification_msg['status'] = 'error'
                    notification_msg['timestamp'] = datetime.datetime.utcnow().isoformat()+'Z'
                    notification_msg['timestamp_ms'] = int(time.time())*1000
                    notification_msg['text'] = 'Failed to process password for user ' + username
                    msg = json.dumps(notification_msg) 
                    client.notify(msg, metadata_uuid)
                    logger.info(msg)
                else:
                    if bad_count == 0:		
                        # Image passed check
                        # Send publish message
                        publish_msg['compliance_check_time'] = datetime.datetime.utcnow().isoformat()+'Z'
                        publish_msg['execution_status'] = "Success"
                        publish_msg['compliant'] = "true"
                        publish_msg['reason'] = "No weak passwords found"
                    else:
                        # Image passed check
                        # Send publish message
                        publish_msg['compliance_check_time'] = datetime.datetime.utcnow().isoformat()+'Z'
                        publish_msg['execution_status'] = "Success"
                        publish_msg['compliant'] = "false"
                        publish_msg['reason'] = "Weak passwords found for users: " + bad_users

                    msg_buf.write(json.dumps(publish_msg))
                    msg_buf.write('\n')
                    client.publish(msg_buf.getvalue(), metadata_uuid)
                    logger.info(json.dumps(publish_msg))

                    # Send notify message
                    notification_msg['status'] = 'completed'
                    notification_msg['timestamp'] = datetime.datetime.utcnow().isoformat()+'Z'
                    notification_msg['timestamp_ms'] = int(time.time())*1000
                    notification_msg['text'] = 'Normal operation'

                    msg = json.dumps(notification_msg)
                    client.notify(msg,metadata_uuid)
                    logger.info(msg)

        except Exception, e:
            logger.exception(e)
            logger.error("Uncaught exception: %s" % e)


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
        parser.add_argument('--receive-topic', type=str, default='config', help='receive-topic')
        parser.add_argument('--notification-topic', type=str, default='notification', help='topic to send notifications')
        parser.add_argument('--annotation-topic', type=str, default='compliance', help='topic to send annotations')
        #parser.add_argument('--elasticsearch-url',  type=str, required=True, help='elasticsearch url: host:port')
        parser.add_argument('--instance-id', type=str, required=True, help='instance id for this annotator')

        args = parser.parse_args()
        #elasticsearch_ip_port = args.elasticsearch_url
        #kafka_ip_port = args.kafka_url
        process_message(args.kafka_url, logger, args.receive_topic, args.annotation_topic, args.notification_topic, args.instance_id)
    except Exception, e:
        print('Error: %s' % str(e))
        logger.exception(e) 
