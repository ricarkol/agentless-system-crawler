import unittest
import logging
import logging.handlers
import imp
import time
import os


class TestMtGraphite(unittest.TestCase):
    def setUp(self):
        # Extract config from hosts.csdev
        self.config = {}
        config_file = open('../../config/hosts.csdev')
        for line in config_file:
            line = line.strip()
            if line and line[0] is not "#" and line[-1] is not "=":
                var, val = line.rsplit("=", 1)
                self.config[var.strip()] = val.strip()

        # Give these two their own variables
        self.dev_graphite_space = self.config['VA_CRAWLER_SPACE_ID'].strip('"')
        self.dev_graphite_url = self.config['VA_CRAWLER_EMIT_URL'].strip('"')

        # Set dummy log name and create logger
        fname = 'dummy_sender.log'
        self._logger = logging.getLogger("crawlutils")
        self._logger.setLevel(logging.DEBUG)
        h = logging.handlers.RotatingFileHandler(
                filename=fname, maxBytes=10e6, backupCount=1)
        f = logging.Formatter(
                '%(asctime)s %(processName)-10s %(levelname)-8s %(message)s')
        h.setFormatter(f)
        self._logger.addHandler(h)

    def test_send_non_stop(self):
        # Get mtgraphite source
        mtgraphite = imp.load_source('mtgraphite', '../../collector/crawler/mtgraphite.py')
        client = mtgraphite.MTGraphiteClient(host_url=self.dev_graphite_url)
        # Send 1000 logs
        for i in range(1000):
            timestamp = int(time.time())
            msg = "%s.0000.tester %d %d\r\n" % (self.dev_graphite_space, 100, timestamp)
            client.send_messages([msg])
            time.sleep(5)
        client.close()
        #### Need an assert here really, perhaps we can check that they are on logmet by logging in?

    def test_send_one_msg(self):
        mtgraphite = imp.load_source('mtgraphite', '../../collector/crawler/mtgraphite.py')
        timestamp = int(time.time())
        client = mtgraphite.MTGraphiteClient(host_url=self.dev_graphite_url, batch_send_every_n=0)
        msg = "%s.0000.tester %d %d\r\n" % (self.dev_graphite_space, 100, timestamp)
        client.send_messages([msg])
        client.close()
        #### Need an assert here really, perhaps we can check that they are on logmet by logging in?
