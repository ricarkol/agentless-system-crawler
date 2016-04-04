#!/usr/bin/env python

# Start this in Docker

import os
import sys
import subprocess
import argparse
import signal

DIRECTORY = '/vagrant/collector/log_crawler/scaletesting/'

# Params in the main 'startScaleTesting.sh' script to which these params will be passed
#BROKERIP="108.168.238.118" 
#BROKERPORT=8081
#SYSTEMPREFIX="scaletestinglaptop03"
#EVENTRATE=1 # 1/sec
#EVENTVOLUME=1 # size of each eventline in KB
#NUMLOGFILES=100 # number of log files to crawl


def cmdline():
    parser = argparse.ArgumentParser(description='Start a logcrawler-scaletest')
    parser.add_argument('--broker-host', required=True,
            help='the hostname of the data broker')
    parser.add_argument('--broker-port', default=8081, type=int,
            help='the port number of the data broker')
    parser.add_argument('--client-id', default='scaletestclient', type=str,
            help='some identifier (e.g. IP) of the logcrawl-scaletest-client')
    parser.add_argument('--event-rate', default=0.1, type=float,
            help="the number of events per sec")
    parser.add_argument('--event-volume', default=1, type=int,
            help='the size of each event line in KB')
    parser.add_argument('--num-logfiles-tocrawl', default=1, type=int,
            help='the number of logfiles to crawl')
    return parser.parse_args()

def main():
    args = cmdline()
    os.chdir(DIRECTORY)
    cmd = [ 'bash', 'start.sh',
        args.broker_host,
        str(args.broker_port),
        args.client_id,
        str(args.event_rate),
        str(args.event_volume),
        str(args.num_logfiles_tocrawl) ]
    print 'Executing command', cmd
    subprocess.check_call(cmd)
    print 'Waiting forever'
    subprocess.check_call([ 'tail', '-f', '/dev/null' ])

def sigterm_handler(signum=None, frame=None):
    print 'Received SIGTERM signal. Stopping ScaleTest'
    os.chdir(DIRECTORY)
    cmd = [ 'bash', 'stop.sh' ]
    print 'Executing command', cmd
    subprocess.check_call(cmd)
    sys.exit(0)
signal.signal(signal.SIGTERM, sigterm_handler)

if __name__ == '__main__':
    main()
