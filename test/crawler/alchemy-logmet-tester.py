import time
import imp
import logging
import logging.handlers
import os
import socket
import subprocess
import argparse
import tempfile

logger = None

def setup_logger(logger_name, logfile='/var/log/alchemy-logmet-tester.log', process_id=None):
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


def test_send_non_stop(url, space_ids):
    setup_logger("crawlutils")

    # Connect to mtgraphite to send logs
    mtgraphite = imp.load_source('mtgraphite', '/opt/cloudsight/collector/crawler/mtgraphite.py')
    print("Connecting to %s" % (url))
    client = mtgraphite.MTGraphiteClient(host_url=url)
    seq = 0

    dummy_logfile = {}
    temp_fd = {}
    temp_filename = {}
    for space_id in space_ids:
        # Create a dummy log file for logcrawler to crawl and send it to logmet
        path = "/var/log/crawler_container_logs/%s/crawler/ping/" % (space_id.replace('.', '/'))
        dummy_log_filename = path + "dummy.log"
        proc = subprocess.Popen("mkdir -p " + path,
                                shell=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE)
        output = proc.stdout.read()
        temp_fd, temp_filename = tempfile.mkstemp(prefix='alchemy-logmet-tester.')
        dummy_logfile[space_id] = open(temp_filename, 'wb')
        os.close(temp_fd) # we already have another FD open for dummy_logfile
        try:
            os.remove(dummy_log_filename)
        except OSError, e:
            print("%s does not exist yet." % dummy_log_filename)
            pass
        os.symlink(temp_filename, dummy_log_filename)

    while True:
        timestamp = int(time.time())
        seq = (seq + 1) % 1000
        hostname = socket.gethostname()

        msgs = []
        for space_id in space_ids:
            # write the dummy log
            tmp_message = "%s: Crawler to logmet test message %d %d (1)\r\n" % (hostname, seq, timestamp)
            dummy_logfile[space_id].write(tmp_message)
            tmp_message = "%s: Crawler to logmet test message %d %d (2)\r\n" % (hostname, seq, timestamp)
            dummy_logfile[space_id].write(tmp_message)
            dummy_logfile[space_id].flush()

            # Create a list of metrics
            msgs.append("%s.crawler.%s.ping %d %d\r\n" % (space_id, hostname, seq, timestamp))

        # send the dummy metrics
        client.send_messages(msgs)
        time.sleep(60)
    client.close()


if __name__ == "__main__":

    stage_url = "mtgraphite://metrics.stage1.opvis.bluemix.net:9095/Crawler:5KilGEQ9qExi"
    prod_url = "mtgraphite://metrics.opvis.bluemix.net:9095/Crawler:oLYMLA7ogscT"

    parser = argparse.ArgumentParser()
    parser.add_argument('--url', dest="url", type=str, default=prod_url, help='Logmet where to send the data to: defaults to mtgraphite://metrics.opvis.bluemix.net:9095/Crawler:<XXX> where <XXX> is the Crawler supertenant password.')
    args  = parser.parse_args()

    # these spaces are: alchemy-test, Sangita's stage, and Ricardo's stage
    test_send_non_stop(args.url, ["1fb90c5d-84e6-452f-a131-9128c565a64f",
                                  "bf8a1339-993f-4c92-a67b-a36effe15818",
                                  "25aa4c07-4a76-43ba-af53-81af7d1733a9",
                                  "2c1c93ec-dbf9-43ef-a2da-cb6759258275.eu-gb"])
