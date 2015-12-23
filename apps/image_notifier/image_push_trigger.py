
from __future__ import print_function
import os
import logging
import time
import signal
import sys
import argparse
import time
import sqlite3
import json

from kafka import SimpleProducer, KafkaClient, KafkaConsumer

logger_name = "push_trigger"
logger_file = "push_trigger.log"

class KafkaInterface(object):
    def __init__(self, kafka_url, logger, receive_topic, publish_topic, notify_topic):
        self.logger        = logger
        self.kafka_url     = kafka_url
        self.kafka         = KafkaClient(kafka_url)
        self.publish_topic = publish_topic
        self.receive_topic = receive_topic
        self.notify_topic = notify_topic

        self.kafka.ensure_topic_exists(receive_topic)
        self.kafka.ensure_topic_exists(publish_topic)
        self.kafka.ensure_topic_exists(self.notify_topic)

    def next_frame(self):
        consumer = KafkaConsumer(self.receive_topic,
                                 group_id=PROCESSOR_GROUP,
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

def get_last_id(args):
    if not os.path.exists(args.triggered_image_ids):
        return 0
    with open(args.triggered_image_ids, 'r') as fp:
        lines =  fp.readlines()
        if lines:
            return lines[-1]
        return 0

def save_last_id(args, id):
    with open(args.triggered_image_ids, 'a') as fp:
        fp.write(str(id))
        fp.write('\n')
        fp.flush()

def get_rows(args, logger, last_id):
    rows = []
    try:
        conn = sqlite3.connect(args.sql_db_file)
        cursor = conn.execute("SELECT id, name from repository where id > {}".format(last_id))
        for row in cursor:
            rows.append((row[0], row[1]))
        conn.close()
    except Exception, e:
        print (str(e))
    return rows

def generate_triggers_for_new_images(args, logger):

    last_id = get_last_id(args)
    rows = get_rows(args, logger, last_id)
    if rows:
        sorted_rows = sorted(rows, key=lambda tup: tup[0])
        save_last_id(args, sorted_rows[-1][0])
        for row in sorted_rows:
            print ('send trigger for image={}'.format(row[1]))
    else:
        print ('empty list')


if __name__ == '__main__':
    format = '%(asctime)s %(levelname)s %(lineno)s %(funcName)s: %(message)s'
    logging.basicConfig(filename=logger_file, filemode='w', format=format, level=logging.INFO)
    logger = logging.getLogger(logger_name)
    sh = logging.StreamHandler(sys.stderr)
    formatter = logging.Formatter(format)
    sh.setFormatter(formatter)
    logger.addHandler(sh)

    try:
        parser = argparse.ArgumentParser(description="")
        parser.add_argument('--kafka-url',  type=str, required=True, help='kafka url: host:port')
        parser.add_argument('--sql-db-file',  type=str, required=True, help='sql database file')
        parser.add_argument('--triggered-image-ids',  type=str, required=True, help='triggered image ids file')
        args = parser.parse_args()
        generate_triggers_for_new_images(args, logger)
    except Exception, e:
        print('Error: %s' % str(e))
        logger.exception(e)
