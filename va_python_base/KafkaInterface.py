
import kafka as kafka_python
import pykafka
from kafka.common import KafkaError
from pykafka.exceptions import KafkaException
import time
from va_python_base.timeout import TimeoutError
from va_python_base.timeout import timeout
from pykafka.common import OffsetType
import random
import sys

kafka_reconnect_after = 60
kafka_send_timeout    = 60
max_read_message_retries = 60
max_kafka_retries     = 600

class TestException(KafkaException):
    pass

# May find a use for these in the near future
class ConsumerConnectException(KafkaException):
    pass

# May find a use for these in the near future
class ConsumerReadException(KafkaException):
    pass

class ProducerConnectException(KafkaException):
    pass

class NotifierConnectException(KafkaException):
    pass

class KafkaInterface(object):

    def __init__(self, kafka_url, kafka_zookeeper_port, logger, receive_topic, publish_topic, notify_topic, processor_group):
        logger.info("===============================")
        logger.info("NEW KAFKA INTERFACE STARTED")
        logger.info("===============================")
        self.logger        = logger
        self.kafka_url     = kafka_url
        self.kafka_zookeeper_port = kafka_zookeeper_port
        self.receive_topic = receive_topic
        self.publish_topic = publish_topic
        self.notify_topic  = notify_topic
        self.processor_group = processor_group
        self.consumer = None
        self.publisher = None
        self.notifier = None

        # XXX replace the port in the broker url. This should be passed.
        if ':' in self.kafka_url:
            self.zookeeper_url = self.kafka_url.rsplit(":", 1)[0] + ":%s" % self.kafka_zookeeper_port
        else:
            self.zookeeper_url = self.kafka_url + ":%s" % self.kafka_zookeeper_port

        logger.info("Kafka URL: "+self.kafka_url)
        logger.info("Zookeeper URL: "+self.zookeeper_url)
        logger.info("Processor Group: "+self.processor_group)
        logger.info("Publish topic: "+self.publish_topic)
        logger.info("Notify topic: "+self.notify_topic)
        logger.info("Receive topic: "+self.receive_topic)
        logger.info("===============================")

        try:
            time.sleep(2)
            self.connect_to_kafka()
            time.sleep(2)
        except KafkaError as error:
            logger.error("Failed to connect to kafka in KafkaInterface init.")
            raise error
        except KafkaException as error:
            logger.error("Failed to connect to kafka in KafkaInterface init.")
            raise error

    def connect_to_kafka(self):
        '''
        XXX autocreate topic doesn't work in pykafka, so let's use kafka-python
        to create one.
        '''
        self.connect_consumer()
        self.connect_publisher()
        self.connect_notifier()
        self.logger.info('Connected to kafka brokers at %s' % self.kafka_url)

    def connect_consumer(self):
        kafka_python_client = self.get_kafka_python_client()
        kafka_python_client.ensure_topic_exists(self.receive_topic)

        pykafka_client = self.get_pykafka_client()
        self.receive_topic_object = pykafka_client.topics[self.receive_topic]
        self.consumer = self.receive_topic_object.get_balanced_consumer(
                                 reset_offset_on_start=True,
                                 fetch_message_max_bytes=512*1024*1024,
                                 consumer_group=self.processor_group,
                                 auto_commit_enable=True,
                                 zookeeper_connect=self.zookeeper_url,
                                 auto_offset_reset=OffsetType.LATEST)

    def connect_notifier(self):
        kafka_python_client = self.get_kafka_python_client()
        kafka_python_client.ensure_topic_exists(self.notify_topic)

        pykafka_client = self.get_pykafka_client()
        self.notify_topic_object = pykafka_client.topics[self.notify_topic]
        self.notifier = self.notify_topic_object.get_sync_producer()

    def connect_publisher(self):
        kafka_python_client = self.get_kafka_python_client()
        kafka_python_client.ensure_topic_exists(self.publish_topic)

        pykafka_client = self.get_pykafka_client()
        self.publish_topic_object = pykafka_client.topics[self.publish_topic]
        self.publisher = self.publish_topic_object.get_sync_producer()

    def get_kafka_python_client(self):
        return kafka_python.SimpleClient(self.kafka_url)

    def get_pykafka_client(self):
        return pykafka.KafkaClient(hosts=self.kafka_url)

    def stop_consumer(self):
        if hasattr(self, 'consumer'):
            self.consumer.stop()
        self.logger.info('Stopped kafka consumer on %s' % self.kafka_url)

    def stop_producer(self):
        if hasattr(self, 'producer'):
            self.publisher.stop()
        self.logger.info('Stopped kafka producer on %s' % self.kafka_url)

    def stop_notifier(self):
        if hasattr(self, 'notifier'):
            self.notifier.stop()
        self.logger.info('Stopped kafka notifier on %s' % self.kafka_url)

    def stop_kafka_clients(self):
        self.stop_consumer()
        self.stop_producer()
        self.stop_notifier()
        self.logger.info('Stopped all kafka clients on %s' % self.kafka_url)

    def next_frame(self):
        message = None
        try:
            self.logger.info("Checking consumer is running")
            if self.consumer._running is False:
                self.logger.info("Consumer is not running - trying again")
                time.sleep(5)

            if self.consumer._running is False:
                self.logger.info("Consumer is not running - exiting")
                sys.exit(1)

            self.logger.info("Attempting to consume")
            message = self.consumer.consume()

            if message is not None:
                self.logger.info("Consumed successfully")
                yield message.value
            else:
                self.logger.info("Consumer received no message")
                raise KafkaException("Consumer received no message")

        except KafkaException as e:
            time.sleep(2)
            self.logger.error('Failed to get new message from kafka: %s'.format(repr(e)))
            raise e

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
                     self.stop_producer()
                     self.connect_publisher()
                     self.stop_notifier()
                     self.connect_notifier()

                except KafkaException as e:
                     self.logger.error('%s: Failed to reconnect to kafka at %s (error=%s)' % (request_id, self.kafka_url, repr(e)))

        if not message_posted:
            raise KafkaError('Failed to publish message to Kafka after %d retries: %s' % (max_kafka_retries, msg))

    def publish(self, data, uuid, namespace):
        try:
            self.post_to_kafka(self.publisher, data, uuid)
        except KafkaError as e:
            self.logger.error('%s: Failed to send publish to kafka for namespace %s: %s' % \
                          (uuid, namespace, repr(e)))

    def notify(self, data, uuid, namespace):
        try:
            self.post_to_kafka(self.notifier,data,uuid)
        except KafkaError as e:
            self.logger.error('%s: Failed to send notification to kafka for namespace %s: %s' % \
                          (uuid, namespace, repr(e)))
