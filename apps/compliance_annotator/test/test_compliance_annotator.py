import logging
import re
import tempfile
import unittest
import os
from StringIO import StringIO

from mock import patch
import mock
from pykafka.exceptions import ProduceFailureError
from apps.compliance_annotator.src import compliance_scanner
import time

log = logging.basicConfig()

def print_all(**args):
    print(" ".join(args))

def sleep_1us():
    time.sleep(0.01)

class TestComplianceAnnotator(unittest.TestCase):

    @patch('time.sleep', side_effect=sleep_1us())
    def test_bad_kafka_connection(self, sleep_mock):
        logger = mock.MagicMock()
        logger.error = mock.Mock(side_effect=print_all())
        logger.info = mock.Mock(side_effect=print_all())
        logger.debug = mock.Mock(side_effect=print_all())

        client = mock.MagicMock()
        client.publish.side_effect=ProduceFailureError
        client.notify.side_effect=ProduceFailureError
        try:
            compliance_scanner.send_notification(client, "{'test':'test'}", "1234567", logger)
            self.assertTrue(False)
        except ProduceFailureError as e:
            pass
        self.assertTrue(logger.error.called)

    @patch('time.sleep', side_effect=sleep_1us())
    def test_bad_kafka_connection(self, sleep_mock):
        logger = mock.MagicMock()
        logger.error = mock.Mock(side_effect=print_all())
        logger.info = mock.Mock(side_effect=print_all())
        logger.debug = mock.Mock(side_effect=print_all())

        client = mock.MagicMock()
        client.publish.side_effect=ProduceFailureError
        client.notify.side_effect=ProduceFailureError
        msg_buf = StringIO()
        msg_buf.write("abc")

        try:
            compliance_scanner.send_publish(client, msg_buf, "1234567", logger)
            self.assertTrue(False)
        except ProduceFailureError as e:
            pass
        self.assertTrue(logger.error.called)

    def test_component_down(self):
        tf = tempfile.NamedTemporaryFile()
        tfName = tf.name
        compliance_scanner.component_down(tfName, "Everything has gone wrong!")
        contents = open(tfName, "r").read()
        self.assertTrue(re.match("DOWN [0-9]+.[0-9]+ Everything has gone wrong!", contents))
