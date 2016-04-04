import time
import imp
import logging
import logging.handlers
import os

logger = None

def setup_logger(logger_name, logfile='dummy_sender.log', process_id=None):
    _logger = logging.getLogger(logger_name)
    _logger.setLevel(logging.DEBUG)
    logfile_name, logfile_xtnsion = os.path.splitext(logfile)
    if process_id == None:
        fname = logfile
    else:
        fname = '{0}-{1}{2}'.format(logfile_name, process_id, logfile_xtnsion)
    h = logging.handlers.RotatingFileHandler(
            filename=fname, maxBytes=10e6, backupCount=1)
    f = logging.Formatter(
            '%(asctime)s %(processName)-10s %(levelname)-8s %(message)s')
    h.setFormatter(f)
    _logger.addHandler(h)


def test_send_non_stop(url):
    setup_logger("crawlutils")
    mtgraphite = imp.load_source('mtgraphite', '../../collector/crawler/mtgraphite.py')
    client = mtgraphite.MTGraphiteClient(host_url=url)
    while True:
        timestamp = int(time.time())
        msg = "d5c00fbb-90b6-4ace-b69a-0e4e7bd28083.0000.12345 %d %d\r\n" % (100, timestamp)
        client.send_messages([msg])
        time.sleep(5)
    client.close()


def test_send_one_msg(url):
    setup_logger("crawlutils")
    mtgraphite = imp.load_source('mtgraphite', '../../collector/crawler/mtgraphite.py')
    timestamp = int(time.time())
    client = mtgraphite.MTGraphiteClient(host_url=url, batch_send_every_n=0)
    msg = "d5c00fbb-90b6-4ace-b69a-0e4e7bd28083.0000.12345 %d %d\r\n" % (100, timestamp)
    client.send_messages([msg])
    client.close()


if __name__ == "__main__":
    stage_url = "mtgraphite://metrics.stage1.opvis.bluemix.net:9095/Crawler:5KilGEQ9qExi"
    prod_url = "mtgraphite://metrics.opvis.bluemix.net:9095/Crawler:oLYMLA7ogscT"
    test_send_non_stop(prod_url)
