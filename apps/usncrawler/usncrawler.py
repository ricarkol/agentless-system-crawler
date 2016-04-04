#!/usr/bin/env python2.7

# Parse Ubuntu Security Notices Atom feed and extract USN information
# The default URL seems to be http://www.ubuntu.com/usn/atom.xml

from __future__ import print_function
import os
import sys
import json
import pprint
import argparse
import datetime
from bs4 import BeautifulSoup
from usntojson import UsnToJson
import requests
import logging
import logging.handlers
import file_store

assert (requests.__version__ >= '2.2.1')

class GetUsnFromFeed(object):
    def __init__(self, data_dir, repo_dir, atom_url, save_data=False):
        self.data_dir = data_dir
        self.repo_dir = repo_dir
        self.atom_url = atom_url
        self.save_data = save_data

    def get_usnids(self, logger):
        r = requests.get(self.atom_url)
        html = r.text
        soup = BeautifulSoup(html, "html.parser")
        for entry in soup.find_all('entry'):
            title = entry.title.contents[0].strip()
            logger.info(title)
            usnid = title.split(':')[0].lower()
            yield usnid

    def do_all(self, logger):
        usnids = list(self.get_usnids(logger))
        usninfos = [ UsnToJson.parseUSN(u, self.data_dir, self.save_data, logger) for u in usnids ]
        # filter  for skipped downloads
        usninfos = [ u for u in usninfos if u]
        return json.loads(json.dumps(usninfos))

def crawl_ubuntu_advisories(logger, usn_url, repo_dir, data_dir, save_data=False):
    logger.info('usn crawl started')
    usn_info_list = GetUsnFromFeed(data_dir=data_dir, repo_dir=repo_dir, atom_url=usn_url, save_data=save_data).do_all(logger)
    if usn_info_list:
        logger.info('start usn save to local repo')
        file_store.FileStore(repo_dir).store_sec_notice_list(sec_notice_list=usn_info_list, logger=logger)
        logger.info('complete usn save to local repo')
    else:
        logger.info('no new usns')
    logger.info('usn crawl finished')

def parse_cmdline():
    parser = argparse.ArgumentParser(
            description="""Parse Ubuntu Security Notices (USN) atom feed
            and store individual usn info in ealstic search index and on local file system given by repo-dir""")
    parser.add_argument('--ubuntu-atom-url', default='http://www.ubuntu.com/usn/atom.xml',
            help='the URL of the Atom feed')
    parser.add_argument('--data-dir', default="./sec_data/data", help='directory for storing original ubuntu security notices')
    parser.add_argument('--repo-dir', default="./sec_data/usnrepo", help='directory for storing processed ubuntu security notices')

    return parser.parse_args()

def main():

    format = '%(asctime)s %(levelname)s %(lineno)s %(funcName)s: %(message)s'
    formatter = logging.Formatter(format)
    
    logger = logging.getLogger("usncrawler")
    logger.setLevel(logging.DEBUG)
    
    fh = logging.handlers.RotatingFileHandler('usncrawler.log', maxBytes=2<<27, backupCount=4)
    fh.setFormatter(formatter)
    fh.setLevel(logging.INFO)
    logger.addHandler(fh)

    args = parse_cmdline()
    logger.info('Arguments received from the command line')
    logger.info(str(vars(args)))

    usninfos = GetUsnFromFeed(data_dir=args.data_dir, repo_dir=args.repo_dir, usn_url=args.ubuntu_atom_url).do_all(logger)

    for item in usninfos:
        usnid = item['id']
        usnpath = os.path.join(args.repo_dir, usnid)
        if not os.path.exists(usnpath):
            with open(usnpath, 'w') as fp:
                fp.write(json.dumps(item, indent=2))
    
if __name__ == '__main__':
    main()
