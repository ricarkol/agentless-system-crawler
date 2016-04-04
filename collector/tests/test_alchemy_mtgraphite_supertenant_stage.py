import time
import imp
import logging
import logging.handlers
import os
import sys


sys.path.append('..')
from setup_logger import setup_logger_stdout
from config_and_metrics_crawler import mtgraphite

def test_send_non_stop(url):
    client = mtgraphite.MTGraphiteClient(host_url=url)
    while True:
        timestamp = int(time.time())
        msg = "%s.0000.12345 %d %d\r\n" % (space_id, 100, timestamp)
        client.send_messages([msg])
        time.sleep(5)
    client.close()


def test_send_one_msg(url, space_id):
    timestamp = int(time.time())
    client = mtgraphite.MTGraphiteClient(host_url=url, batch_send_every_n=0)
    msg = "%s.0000.12345 %d %d\r\n" % (space_id, 100, timestamp)
    client.send_messages([msg])
    client.close()


if __name__ == "__main__":
    setup_logger_stdout("crawlutils")
    stage_url = "mtgraphite://metrics.stage1.opvis.bluemix.net:9095/Crawler:5KilGEQ9qExi"
    test_send_one_msg(stage_url, 'd5c00fbb-90b6-4ace-b69a-0e4e7bd28083')
