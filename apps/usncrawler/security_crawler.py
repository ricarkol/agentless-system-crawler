#!/usr/bin/env python2.7

from __future__ import print_function
import os
import sys
import time
import json
import pprint
import argparse
from datetime import datetime, timedelta
import logging
import logging.handlers
import urllib3

import file_store
import ubuntu_crawler
import rhncrawler
import centos_crawler
import debian_crawler
import elastic_index
import timeout


LOG_FILE_NAME = "security_notices.log"
logger   = None

RHN_URL = 'https://rhn.redhat.com'
CENTOS_URL='https://lists.centos.org/pipermail/centos-announce/'
UBUNTU_URL='https://lists.ubuntu.com/archives/ubuntu-security-announce/'
UBUNTU_ATOM_URL='http://www.ubuntu.com/usn/atom.xml'
DEBIAN_URL='https://lists.debian.org/debian-security-announce/'
DATA_ROOT="sec_data"
REPO_DIR = 'usnrepo'
DATA_DIR = 'data'
LOG_DIR = '/var/log/cloudsight/'
REDHAT_TIMEOUT=3600             # on iris vm it takes about 30+ minutes to download rhel server 6, 7 advisories
CENTOS_TIMEOUT=300              # on iris vm it takes about 150 seconds to download full debian 
UBUNTU_TIMEOUT=60               # typical ubuntu full advisory crawl takes about 20 seconds
DEBIAN_TIMEOUT=120              # on iris machine it tabkes about 60 seconds to download debian

#
# patch schema:
#
# {
#   id* (rhsa-2015:0816)
#   site* (http://www.xyz.com)
#   category* (security, enhancement, bugfix)
#   cveid (xyz)
#   vendor (redhat, ubuntu)
#   severity (low, medium, high, critical)
#   releasedate (2015-01-01)
#   summary* (firefox vulnerability)
#   fixes[]*
#     os*
#        name* (rhel)
#        version* (7.0)
#        architecture (32-bit)
#        distribution (server)
#     package[]
#         name*
#         version*
#         release
#     

def parse_cmdline():
    parser = argparse.ArgumentParser(
            description="""Parse Security Notices from Red Hat, CentOS, and Ubuntu and store in ealstic search index and on local dir data""")
    parser.add_argument('--data-root', default=DATA_ROOT, help='Location to store data')
    parser.add_argument('--ubuntu-url', default=UBUNTU_URL, help='the url of the ubuntu-security-announce Archives')
    parser.add_argument('--rhn-url', default=RHN_URL, help='URL of the RHN website')
    parser.add_argument('--centos-url', default=CENTOS_URL, help='the url of the CentOS-announce Archives')
    parser.add_argument('--debian-url', default=DEBIAN_URL, help='the url of the Debian Mailing Lists: debian-security-announce')
    parser.add_argument('--elastic-search', help='elastic search host')
    parser.add_argument('--save-data', action="store", default=False, help='elastic search host')
    parser.add_argument('--sleeptime', default=84600,  type=int, help='sleep time in second')

    return parser.parse_args()

def load_index_from_filerepo(logger, repo_dir, elastic_search):
    if elastic_search:
        logger.info('start loading security notices to elasticsearch')
    else:
        logger.info('No elastic_search option specified. Skipping indexing.')
        return

    try:
        usn_info_list = file_store.FileStore(repo_dir).get_all_usn(logger)
    except Exception, e:
        usn_info_list = []
        logger.error(e)

    logger.info('start security notices save to elasticsearch')
    elastic_index.Index(elastic_host=elastic_search).load_index(usn_info_list, logger)
    logger.info('completed security notices save to elasticsearch')

@timeout.timeout(REDHAT_TIMEOUT)
def perform_rhn_crawl(logger, url, repo_dir, data_dir, save_data):
    try:
        rhncrawler.crawl_rhn_advisories(logger, rhn_url=url, repo_dir=repo_dir, data_dir=data_dir, save_data=save_data)
    except timeout.TimeoutError, e:
       logger.warn('could not complete crawl of redhat security advisories in {} seconds'.format(REDHAT_TIMEOUT))

@timeout.timeout(CENTOS_TIMEOUT)
def perform_centos_crawl(logger, url, repo_dir, data_dir, save_data):
    try:
        centos_crawler.crawl_centos_advisories(logger, centos_url=url, repo_dir=repo_dir, data_dir=data_dir, save_data=args.save_data)
    except timeout.TimeoutError, e:
       logger.warn('could not complete crawl of centos security advisories in {} seconds'.format(CENTOS_TIMEOUT))

@timeout.timeout(DEBIAN_TIMEOUT)
def perform_debian_crawl(logger, url, repo_dir, data_dir, save_data):
    try:
        debian_crawler.crawl_debian_advisories(logger, debian_url=url, repo_dir=repo_dir, data_dir=data_dir, save_data=save_data)
    except timeout.TimeoutError, e:
       logger.warn('could not complete crawl of debian security advisories in {} seconds'.format(DEBIAN_TIMEOUT))

@timeout.timeout(UBUNTU_TIMEOUT)
def perform_ubuntu_crawl(logger, url, repo_dir, data_dir, save_data):
    try:
        ubuntu_crawler.crawl_ubuntu_advisories(logger, ubuntu_url=url, repo_dir=repo_dir, data_dir=data_dir) 
    except timeout.TimeoutError, e:
       logger.warn('could not complete crawl of ubuntu security advisories in {} seconds'.format(UBUNTU_TIMEOUT))

def security_crawler(logger, args):

    logger.info('Arguments received from the command line')
    logger.info(str(vars(args)))
    try:

        repo_dir = os.path.join(args.data_root,REPO_DIR)
        data_dir = os.path.join(args.data_root,DATA_DIR)

        load_index_from_filerepo(logger=logger, repo_dir=repo_dir, elastic_search=args.elastic_search)
        while True:

            logger.info ('debian start: {}'.format(datetime.now()))
            perform_debian_crawl(logger, url=args.debian_url, repo_dir=repo_dir, data_dir=data_dir, save_data=args.save_data)
            logger.info ('ubuntu start: {}'.format(datetime.now()))
            perform_ubuntu_crawl(logger, url=args.ubuntu_url, repo_dir=repo_dir, data_dir=data_dir, save_data=args.save_data) 
            logger.info ('rhn start: {}'.format(datetime.now()))
            perform_rhn_crawl(logger, url=args.rhn_url, repo_dir=repo_dir, data_dir=data_dir, save_data=args.save_data)
            logger.info ('centos start: {}'.format(datetime.now()))
            perform_centos_crawl(logger, url=args.centos_url, repo_dir=repo_dir, data_dir=data_dir, save_data=args.save_data)
            logger.info ('centos end: {}'.format(datetime.now()))
           
            load_index_from_filerepo(logger=logger, repo_dir=repo_dir, elastic_search=args.elastic_search)
            now = datetime.now()
            logger.info('last crawl: {}'.format(now.isoformat()))
            logger.info('next crawl around {}'.format((now+timedelta(seconds=args.sleeptime)).isoformat()))
            print ('going to sleep')
            time.sleep(args.sleeptime)

    except Exception, e:
        logger.exception(e)
        raise e

if __name__ == '__main__':

    log_file = os.path.join(LOG_DIR, LOG_FILE_NAME)
    if not os.path.exists(LOG_DIR):
        os.makedirs(LOG_DIR)
        os.chmod(LOG_DIR,0755)

    format = '%(asctime)s %(levelname)s %(lineno)s %(funcName)s: %(message)s'
    formatter = logging.Formatter(format)
    
    logger = logging.getLogger("security_crawler")
    logger.setLevel(logging.DEBUG)
    
    fh = logging.handlers.RotatingFileHandler(log_file, maxBytes=2<<27, backupCount=4)
    fh.setFormatter(formatter)
    fh.setLevel(logging.INFO)
    logger.addHandler(fh)

    args = parse_cmdline()
    urllib3.disable_warnings()

    security_crawler(logger, args)
    
