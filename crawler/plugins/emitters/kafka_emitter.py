import Queue
import logging
import multiprocessing
import os
import shutil
import tempfile
import time

import kafka as kafka_python
import pykafka

try:
    from crawler_exceptions import EmitterBadURL, EmitterEmitTimeout
    from crawler_exceptions import (EmitterUnsupportedFormat)
    from plugins.emitters.base_emitter import BaseEmitter
    from misc import NullHandler
except ImportError:
    from crawler.crawler_exceptions import EmitterBadURL, EmitterEmitTimeout
    from crawler.crawler_exceptions import (EmitterUnsupportedFormat)
    from crawler.plugins.emitters.base_emitter import BaseEmitter
    from crawler.misc import NullHandler

logger = logging.getLogger('crawlutils')
# Kafka logs too much
logging.getLogger('kafka').addHandler(NullHandler())


def kafka_send(kurl, temp_fpath, format, topic, queue=None):
    try:
        kafka_python_client = kafka_python.KafkaClient(kurl)
        kafka_python_client.ensure_topic_exists(topic)
        kafka = pykafka.KafkaClient(hosts=kurl)
        print queue
        publish_topic_object = kafka.topics[topic]
        # the default partitioner is random_partitioner
        producer = publish_topic_object.get_producer()

        if format == 'csv':
            with open(temp_fpath, 'r') as fp:
                text = fp.read()
                producer.produce([text])
        elif format == 'graphite':
            with open(temp_fpath, 'r') as fp:
                for line in fp.readlines():
                    producer.produce([line])
        else:
            raise EmitterUnsupportedFormat('Unsupported format: %s' % format)

        queue and queue.put((True, None))
    except Exception as exc:
        if queue:
            queue.put((False, exc))
        else:
            raise
    finally:
        queue and queue.close()


class KafkaEmitter(BaseEmitter):

    def emit(self, iostream, compress=False,
             metadata={}, snapshot_num=0):
        """

        :param iostream: a CStringIO used to buffer the formatted features.
        :param compress:
        :param metadata:
        :param snapshot_num:
        :return:
        """
        if compress:
            raise NotImplementedError('kafka emitter does not support gzip.')
        self._publish_to_kafka(iostream, self.url)

    def _publish_to_kafka_no_retries(self, iostream, url):

        list = url[len('kafka://'):].split('/')

        if len(list) == 2:
            kurl, topic = list
        else:
            raise EmitterBadURL(
                'The kafka url provided does not seem to be valid: %s. '
                'It should be something like this: '
                'kafka://[ip|hostname]:[port]/[kafka_topic]. '
                'For example: kafka://1.1.1.1:1234/metrics' % url)

        # TODO: fix this mess. Why are we creating a file to pass its
        # path to a new process created just for sending messages to kafka?
        (temp_fd, temp_fpath) = tempfile.mkstemp(prefix='emit.')
        os.close(temp_fd)  # close temporary file descriptor
        with open(temp_fpath, 'w') as fd:
            iostream.seek(0)
            shutil.copyfileobj(iostream, fd)

        queue = multiprocessing.Queue()
        try:
            try:
                child_process = multiprocessing.Process(
                    name='kafka-emitter', target=kafka_send, args=(
                        kurl, temp_fpath, 'graphite', topic, queue))
                child_process.start()
            except OSError:
                raise

            try:
                (result, child_exception) = queue.get(
                    timeout=self.timeout)
            except Queue.Empty:
                child_exception = EmitterEmitTimeout()

            child_process.join(self.timeout)

            if child_process.is_alive():
                errmsg = ('Timed out waiting for process %d to exit.' %
                          child_process.pid)
                os.kill(child_process.pid, 9)
                logger.error(errmsg)
                raise EmitterEmitTimeout(errmsg)

            if child_exception:
                raise child_exception
        finally:
            queue.close()

    def _publish_to_kafka(self, iostream, url):
        broker_alive = False
        retries = 0
        while not broker_alive and retries <= self.max_retries:
            try:
                retries += 1
                self._publish_to_kafka_no_retries(iostream, url)
                broker_alive = True
            except Exception as exc:
                logger.debug(
                    '_publish_to_kafka_no_retries {0}: {1}'.format(
                        url, exc))
                if retries <= self.max_retries:

                    # Wait for (2^retries * 100) milliseconds

                    wait_time = 2.0 ** retries * 0.1
                    logger.error(
                        'Could not connect to the kafka server at %s. Retry '
                        'in %f seconds.' % (url, wait_time))
                    time.sleep(wait_time)
                else:
                    raise exc
