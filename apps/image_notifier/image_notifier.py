from __future__ import print_function
import fnmatch
import copy
import os
import logging
import time
import sys
import argparse
import time
import json
from datetime import datetime

from kafka import SimpleProducer, KafkaClient, KafkaConsumer

logger_name = "image_notifier"
logger_file = "image_notifier.log"

#repo_dir = '/mnt/data/docker-registry/registry/repositories'
#previous_image_tag_file = 'previous_image_tags'


class KafkaInterface(object):
    def __init__(self, kafka_url, logger, notify_topic):
        self.logger        = logger
        self.kafka_url     = kafka_url
        self.kafka         = KafkaClient(kafka_url)
        self.notify_topic = notify_topic
        self.kafka.ensure_topic_exists(self.notify_topic)

    def _publish(self, topic, data):
        producer = SimpleProducer(self.kafka)
        ret = producer.send_messages(topic, data)
        producer.stop()
        if ret:
            self.logger.debug("Published offset %s: %s" % (ret[0].offset, ret[0].error))

    def notify(self, data):
        self._publish(self.notify_topic, data)

def load_image_tags(args, logger):
    try:
        with open(args.image_tag_file, 'r') as wp:
            return json.load(wp)
    except Exception, e:
        logger.error(e)
    return {}

def save_image_tags(args, image_tags, logger):
    logger.info('Saving current tags')
    with open(args.image_tag_file, 'w') as wp:
        wp.write(json.dumps(image_tags, indent=2))


def generate_image_notifications(args, logger):
    '''
    crawls the repository directory, generates current image:tag list,
    removes all those that are present in previous set, and sends notifications
    for all the remaining ones
    '''

    client = KafkaInterface(args.kafka_url, logger, args.image_notification_topic)

    while True:
        previous_image_tags = load_image_tags(args, logger)
        current_image_tags = {}
        for repo in os.listdir(args.repository_dir):
            images = os.listdir(os.path.join(args.repository_dir, repo)) 
            for image in images:
                for f in os.listdir(os.path.join(args.repository_dir, repo, image)): 
                    if fnmatch.fnmatch(f, 'tag_*'):
                        image_id="none"
                        with open(os.path.join(args.repository_dir, repo, image, f), 'r') as fp:
                            image_id = fp.read()
                        if repo == 'library':
                            repo_image_tag = '{}/{}:{}'.format(args.registry_host, image, f[4:])
                            repo_str = '{}/{}'.format(args.registry_host, image)
                        else:
                            repo_image_tag = '{}/{}/{}:{}'.format(args.registry_host, repo, image, f[4:])
                            repo_str = '{}/{}/{}'.format(args.registry_host, repo, image)

                        current_image_tags[repo_image_tag] = { 'tag': f[4:], 'id' :image_id, 'full_image': repo_image_tag, 'repository' : repo_str, 'timestamp': datetime.utcnow().isoformat()}
    
        notify_image_tags = copy.deepcopy(current_image_tags)
        for img_tag, value in previous_image_tags.iteritems():
            try:
                if img_tag in notify_image_tags:
                    if notify_image_tags[img_tag]['id'] == value['id']:
                        del notify_image_tags[img_tag]
            except ValueError, e:
                logger.error('missing from current={}, removed?'.format(img_tag))
    
        try:
            for img_tag in notify_image_tags:
                client.notify(json.dumps(notify_image_tags[img_tag]))
                print ('notifying={}'.format(img_tag))
            save_image_tags(args, current_image_tags, logger)
        except Exception, e:
            logger.exception(e)
    
        #logger.info('notified: {}'.format(json.dumps(notify_image_tags, indent=2)))
        time.sleep(2)

if __name__ == '__main__':
    format = '%(asctime)s %(levelname)s %(lineno)s %(funcName)s: %(message)s'
    logging.basicConfig(format=format, level=logging.INFO)
    logger = logging.getLogger(logger_name)

    try:
        parser = argparse.ArgumentParser(description="")
        parser.add_argument('--kafka-url',  type=str, required=True, help='kafka url: host:port')
        parser.add_argument('--repository-dir',  type=str, required=True, help='root directory docker-registry repository file, eg., /mnt/data/docker-registry/registry/repositories')
        parser.add_argument('--image-tag-file',  type=str, required=True, help='file to store image tags compiled in current run')
        parser.add_argument('--registry-host',  type=str, required=True, help='docker registry host which will be appended to the image')
        parser.add_argument('--image-notification-topic',  type=str, required=True, help='kafka topic to send image notifications')
        args = parser.parse_args()
        generate_image_notifications(args, logger)
    except Exception, e:
        print('Error: %s' % str(e))
        logger.exception(e)
