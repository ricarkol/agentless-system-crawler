import pingpy
import multiprocessing
import time
import socket
import imp
import argparse
import os
import logging
import logging.handlers
import mtgraphite

def setup_logger(logger_name, logfile='/var/log/va-pinger.log', process_id=None):
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



def dump_queue(queue):
    """
    Empties all pending items in a queue and returns them in a list.
    """
    result = []

    for i in iter(queue.get, 'STOP'):
        result.append(i)
    time.sleep(.1)
    return result

def ping_func(dest_addr, result_queue, duration):
    res = pingpy.quiet_ping(dest_addr, timeout=2, duration=duration, sleep=1)
    result_queue.put((dest_addr, res))

def ping_test(dest_addrs, duration):
    processs = []
    result_queue = multiprocessing.Queue()
    for dest_addr in dest_addrs:
	process = multiprocessing.Process(target=ping_func, args=[dest_addr, result_queue, duration])
	process.start()
	processs.append(process)

    for process in processs: # then kill them all off
	process.join()
	process.terminate()

    result_queue.put('STOP')
    return dump_queue(result_queue)

def ping_and_report_to_mtgraphite_non_stop(url, space_id, dest_addrs, duration):
    setup_logger("crawlutils")

    # Connect to mtgraphite to send logs
    client = mtgraphite.MTGraphiteClient(host_url=url)

    hostname = socket.gethostname().replace('.', '_')

    while True:
        results = ping_test(dest_addrs, duration)
        timestamp = int(time.time())
        msgs = []
        for res in results:
            # Create a list of metrics
            dest_addr, (percent_lost, avg, p95, p99) = res
            dest_addr = dest_addr.replace('.', '_')
            msgs.append("%s.va.pings.%s.%s.percent_lost %d %d\r\n" % (space_id, hostname, dest_addr, percent_lost, timestamp))
            msgs.append("%s.va.pings.%s.%s.rtt.avg %d %d\r\n" % (space_id, hostname, dest_addr, avg, timestamp))
            msgs.append("%s.va.pings.%s.%s.rtt.percentile95 %d %d\r\n" % (space_id, hostname, dest_addr, p95, timestamp))
            msgs.append("%s.va.pings.%s.%s.rtt.percentile99 %d %d\r\n" % (space_id, hostname, dest_addr, p99, timestamp))
        client.send_messages(msgs)
        #for msg in msgs:
        #    print msg

if __name__ == '__main__':
    stage_url = "mtgraphite://metrics.stage1.opvis.bluemix.net:9095/Crawler:5KilGEQ9qExi"
    canturk_stage_space_id = "7ee49029-dbea-4998-b12b-b602d305af4e"
    canturk_prod_space_id = "c85ea631-d4cb-4f29-8489-f456adf36f08"
    dest_addrs = ["logs.opvis.bluemix.net", "metrics.opvis.bluemix.net"]

    parser = argparse.ArgumentParser()
    parser.add_argument('--url', dest="url", type=str, default=stage_url, help='Logmet where to send the data to: defaults to mtgraphite://metrics.opvis.bluemix.net:9095/Crawler:<XXX> where <XXX> is the Crawler supertenant password.')
    parser.add_argument('--space', dest="space", type=str, default=stage_url, help='Space ID to use for the metrics.')
    parser.add_argument('--addrs', dest="addrs", type=str, default=stage_url, help='Comma separated list of destination addresses (IP or names accepted).')
    parser.add_argument('--duration', dest="duration", type=int, default=300, help='Duration of a ping test. Defaults to 5 minutes.')
    args  = parser.parse_args()

    ping_and_report_to_mtgraphite_non_stop(args.url, args.space, args.addrs.split(","), args.duration)
