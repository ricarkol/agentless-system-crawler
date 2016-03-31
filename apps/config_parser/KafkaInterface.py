import csv
import json
import pykafka
import sys
import signal
try:
    from cStringIO import StringIO
except:
    from StringIO import StringIO

from functools import wraps
from pykafka.exceptions import KafkaException
import kafka as kafka_python
import os
import errno
from retry import retry
import time
import datetime
max_kafka_retries     = 600
max_read_message_retries = 60
kafka_reconnect_after = 60
kafka_send_timeout    = 60
processor_group       = "config-parser"

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
        self.consumer_retry_count = 0
        self.last_consumer_retry_count = 0
        self.consumer = None
        self.producer = None
        self.notifier = None

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

    def next_frame(self):
        message = None
        for i in range(max_read_message_retries):
            sleep_duration = i * 0.1
            if sleep_duration > 2.0:
                sleep_duration = 2
            time.sleep(sleep_duration)
            try:
                try:
                    #### TEST BLOCK ####
                    if self.test and not self.consumer_test_complete:
                        self.logger.info("TEST --------- Testing that consumer is running.")

                        assert self.consumer._running is True
                        self.logger.info("TEST --------- Consumer is running, skipping attempt to consume, will restart kafka connection.")
                        self.consumer_test_complete = True
                        raise TestException("Test")
                    #### TEST BLOCK END ####
                    self.logger.info("Attempting to consume")
                    message = self.consumer.consume()
                except KafkaException as e:
                    self.consumer_retry_count += 1
                    self.logger.error('Failed to get new message from kafka: %s' % repr(e))
                    self.logger.error('Retry attempt: {}'.format(self.consumer_retry_count))
                    if self.consumer._running is True:
                        self.logger.info("Consumer running, stopping Kafka Clients")
                        self.stop_kafka_clients()
                        time.sleep(1)
                    self.connect_to_kafka()
                    time.sleep(1)
                    self.logger.error("Kafka restart attempted {}".format(self.kafka_url))
                    raise KafkaException("Kafka restart attempted {}".format(self.kafka_url))

                self.logger.info("Consumed successfully")
                self.consumer_retry_count = 0
                self.last_consumer_retry_count = 0
                if message is not None:
                    yield message.value

            except KafkaException as err:
                if i == max_read_message_retries -1:
                    raise err


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