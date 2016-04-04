#!/usr/bin/env python2.7

from __future__ import print_function
import sys
import requests
import re
import traceback
import os
import argparse
import time
import datetime
import logging
import logging.handlers
import simplejson as json
from multiprocessing import Pool
from bs4 import BeautifulSoup
from rpmUtils.miscutils import splitFilename
import urllib3

import copy

RHN_URL = 'https://rhn.redhat.com'
CENTOS_URL='https://lists.centos.org/pipermail/centos-announce/'
DATA_ROOT="sec_data"
REPO_DIR = 'usnrepo'
DATA_DIR = 'data'
LOG_DIR = '/var/log/cloudsight/'
SLEEPTIME = 300

logger = None

supported = [
    {'distribution':'server', 'version':['6'], 'type':['security'], 'arch':'x86_64'},
    {'distribution':'server', 'version':['7'], 'type':['security'], 'arch':'x86_64'}
]

def getErratas(logger, s, rhn_url):
    url = rhn_url+'/errata/rhel-'+s['distribution']+'-'+s['version']+'-errata'
    if 'type' in s:
        url += '-'+s['type']
    url += '.html'

    try:
        response = requests.get(url)
    except requests.exceptions.RequestException as e:
        logger.warn('Error while fetching package vulnerabilities:url={}, reason={}'.format(url,str(e)))
        return

    soup = BeautifulSoup(response.text, "html.parser")

    '''
    soup = BeautifulSoup(open('test.html', 'r'))
    '''
    scripts = soup.select('script[type=text/javascript]')
    data = None
    for script in scripts:
        text = script.get_text()
        if text.find('errataTableData') != -1:
            data = text.encode('ascii', 'ignore')
            break
    if data == None:
        logger.error('Cannot parse data')
        return None

    start = data.find('[')
    if start == -1:
        logger.error('Cannot parse data')
        return None

    erratas = []
    i = start+1
    stack = ['[']
    while len(stack) > 0:
        if data[i] == '[':
            stack.append('[')
            start = i+1
        elif data[i] == ']':
            stack.pop()
            if len(stack) > 0:
                try :
                    m = re.match(u'\'(.)*\',\'(.*)\',\'(.*)\',\'(.*)\',\'(.*)\'', data[start:i])
                    x = {}
                    x['severity'] = m.group(2)
                    x['id'] = m.group(3)
                    x['releasedate'] = m.group(5)
                    n = re.match(u'.* href=\"(.*)\">(.*)</a>', m.group(4))
                    x['site'] = rhn_url+n.group(1)
                    x['summary'] = n.group(2)
                    x['category'] = s['type']
                    x['cveid'] = ''
                    x['vendor'] = 'redhat'
                    x['os'] = {}
                    x['os']['name'] = 'rhel'
                    x['os']['version'] = s['version']
                    x['os']['architecture'] = s['arch']
                    x['os']['distribution'] = s['distribution']
                    erratas.append(x)
                except:
                    logger.error('Cannot parse data: '+data[start:i])
                    return None
        i += 1
    return erratas

def getPackages(logger, errata, repo_dir, data_dir, rhn_url, save_data=False):

    startDistribution = False
    currentArch = None
    url = errata['site']
    skip_len = len(rhn_url) + len ('errata') + 2
    _fname = '{}-{}-{}'.format(errata['os']['distribution'], errata['os']['version'], url[skip_len:])
    fname = os.path.join(data_dir, _fname)
    if os.path.exists(fname):
        return
    print(fname)
    try:
        response = requests.get(url)
    except requests.exceptions.RequestException as e:
        logger.warn('Error while fetching package vulnerabilities:url={}, reason={}'.format(url,str(r)))
        return

    # record filename, save content if enabled 
    with open(fname, 'w') as fp:
        if save_data:
            fp.write(response.text.encode('utf-8'))
            
    soup = BeautifulSoup(response.text, "html.parser")
    table = soup.select('table[border]')[0]
    logger.debug('Found '+errata['id']+' at '+errata['site'])
    children = table.contents
    for child in children:
        if child.name == 'tr':
            grandchildren = child.contents
            for grandchild in grandchildren:
                if grandchild.name == 'td':
                    grandchildText = grandchild.get_text().encode('ascii', 'ignore')

                    # Ignore empty rows
                    if len(grandchildText) == 0:
                        continue

                    # See if this is a header for a particular distribution
                    m = re.match(u'Red Hat Enterprise Linux (.+) \(v\. (.+)\)', grandchildText)
                    if m != None:
                        if m.group(1).upper() == errata['os']['distribution'].upper() and \
                            m.group(2) == errata['os']['version']:
                            logger.debug(m.group(1)+' '+ m.group(2))
                            startDistribution = True
                        else:
                            startDistribution = False
                        break

                    # See if this is a header for a particular architecture
                    m = re.match(u'([\w-]+):', grandchildText)
                    if m != None:
                        if startDistribution and (m.group(1).upper() == errata['os']['architecture'].upper()):
                            logger.debug('\t'+m.group(1))
                            currentArch = m.group(1).upper()
                        else:
                            currentArch = None
                        break

                    # See if this is a package
                    if startDistribution and currentArch != None:
                        m = re.match(u'(.+\.rpm)', grandchildText)
                        if m != None:
                            logger.debug('\t\t'+m.group(1))
                            if 'fixes' not in errata:
                                errata['fixes'] = []

                            (n,v,r,e,a) = splitFilename(m.group(1))

                            found = False
                            for fix in errata['fixes']:
                                OS = fix['os']
                                if (OS['distribution'] == errata['os']['distribution'] and
                                    OS['version'] == errata['os']['version'] and
                                    OS['name'] == errata['os']['name'] and
                                    OS['architecture'] == errata['os']['architecture']):
                                    p = {}
                                    p['name'] = n
                                    p['version'] = v
                                    p['release'] = r
                                    fix['packages'].append(p)
                                    found = True
                                    break

                            if not found:
                                x = {}
                                x['os'] = errata['os']
                                p = {}
                                p['name'] = n
                                p['version'] = v
                                p['release'] = r
                                x['packages'] = [p]
                                errata['fixes'].append(x)
                            break

    del errata['os']

    # duplicate for centos
    if 'fixes' in errata:
        tmp = copy.deepcopy(errata['fixes'])
        for t in tmp:
            if t['os']['name'] == 'rhel':
                t['os']['name'] = 'centos'
                errata['fixes'].append(t)

    filePath = os.path.join(repo_dir, errata['id'])
    logger.info('saving {}'.format(filePath))
    f = open(filePath, 'w')
    f.write(json.dumps(errata, indent=2))
    f.close()

def getArgs():
    parser = argparse.ArgumentParser(description='Fetch advisories from Redhat Network website')
    parser.add_argument('-d', '--data-root', default=DATA_ROOT, help='Location to store data')
    parser.add_argument('-l', '--log-dir', default=LOG_DIR, help='Location to store logs')
    parser.add_argument('--rhn-url', default=RHN_URL, help='URL of the RHN website')
    parser.add_argument('--centos-url', default=CENTOS_URL, help='URL of the RHN website')
    parser.add_argument('--sleeptime', default=SLEEPTIME, help='sleep time between pulls in seconds')
    return parser.parse_args()

def initialize(args):
    global DATA_DIR, LOG_DIR, RHN_URL, SLEEPTIME,  logger

    DATA_ROOT = args.data_root
    if not os.path.exists(DATA_ROOT):
        os.mkdir(DATA_ROOT)

    LOG_DIR = args.log_dir
    if not os.path.exists(LOG_DIR):
        os.mkdir(LOG_DIR)

    RHN_URL = args.rhn_url
    SLEEPTIME = args.sleeptime

    LOG_FILE = LOG_DIR + '/rhncrawler.log'
    format = '%(asctime)s %(levelname)s %(lineno)s %(funcName)s: %(message)s'
    formatter = logging.Formatter(format)
    logger = logging.getLogger('rhncrawler')
    logger.setLevel(logging.DEBUG)
    fh = logging.handlers.RotatingFileHandler(LOG_FILE, maxBytes=2<<27, backupCount=4)
    fh.setFormatter(formatter)
    fh.setLevel(logging.DEBUG)
    logger.addHandler(fh)

def readPatchesFromDir():
    results = []
    if os.path.exists(DATA_DIR):
        for root, dirs, files in os.walk(DATA_DIR):
            for name in files:
                try:
                    results.append(json.load(open(os.path.join(root, name))))
                except Exception, e:
                    logger.error (e)
                    raise e
    return results

#def rhncrawl():
#    logger.info('RHNCrawler starts')
#    workers = Pool(THREADS)
#    for s in supported:
#        for version in s['version']:
#            for t in s['type']:
#                param = {
#                    'distribution':s['distribution'], 
#                    'version':version,
#                    'type':t,
#                    'arch':s['arch']
#                    }
#                erratas = getErratas(param)
#                workers.map(getPackages, erratas, rhn_url)
#    workers.close()
#    workers.join()
#
#    patches = readPatchesFromDir()
#    elastic_index.Index(elastic_host=ES_HOST).load_index(patches, logger)
#
#    logger.info('RHNCrawler finished')

def crawl_rhn_advisories(logger, rhn_url, repo_dir, data_dir, save_data=False):
    logger.info('RHNCrawler starts')
    for s in supported:
        for version in s['version']:
            for t in s['type']:
                param = {
                    'distribution':s['distribution'], 
                    'version':version,
                    'type':t,
                    'arch':s['arch']
                    }
                for errata in getErratas(logger, param, rhn_url):
                    getPackages(logger, errata, repo_dir, data_dir, rhn_url, save_data=False)

    logger.info('RHNCrawler finished')

if __name__ == '__main__':
    urllib3.disable_warnings()
    args = getArgs()
    initialize(args)

    repo_dir = os.path.join(args.data_root, REPO_DIR)
    data_dir = os.path.join(args.data_root, DATA_DIR)
    now = datetime.datetime.now()
    crawl_rhn_advisories(logger, repo_dir, data_dir)
    print ('done')
    logger.info('next crawl around {}'.format((now+datetime.timedelta(seconds=SLEEPTIME)).isoformat()))

