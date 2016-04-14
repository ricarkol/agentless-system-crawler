import logging
import re
import tempfile
import unittest
import os
from StringIO import StringIO

from mock import patch
import mock
from pykafka.exceptions import ProduceFailureError
from apps.compliance_annotator import compliance_scanner
import time

log = logging.basicConfig()

def print_all(**args):
    print(" ".join(args))

def sleep_1us():
    time.sleep(0.01)

class TestComplianceAnnotator(unittest.TestCase):

    def test_component_down(self):
        tf = tempfile.NamedTemporaryFile()
        tfName = tf.name
        compliance_scanner.component_down(tfName, "Everything has gone wrong!")
        contents = open(tfName, "r").read()
        self.assertTrue(re.match("DOWN [0-9]+.[0-9]+ Everything has gone wrong!", contents))
