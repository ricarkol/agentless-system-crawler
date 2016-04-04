import os
import requests
from bs4 import BeautifulSoup
import zlib
import urllib3
import json
import logging
import logging.handlers
import re
from datetime import datetime
import itertools

SUSE_URL='http://lists.opensuse.org/opensuse-security-announce/'
YEAR_MONTH_REGEX = re.compile('opensuse-security-announce-(\d+)-(\d+).mbox.gz')
CUT_OFF_YEAR = 2012
SUSE_FILE_PREFIX = 'suse'
SUSE_DATE_MONTH_FORMAT = '%Y-%m'

def process_archive(logger, year, month, url, repo_dir, data_dir, save_data):

    try:
        response = requests.get(url)
    except requests.exceptions.RequestException as e:
        logger.warn('Error while fetching package vulnerabilities: url={}, reason={}'.format(ubuntu_url, str(e)))
        return
    

def crawl_suse_advisories(logger, url, repo_dir, data_dir, save_data=False):

    def find_advisory_date(advisory_fname):
        sp = advisory_fname.split('-')
        return datetime.strptime('{}-{}'.format(sp[1],sp[2].split('.')[0]), SUSE_DATE_MONTH_FORMAT)

    def find_latest_suse_advisory_date(data_dir):
        import glob
        flist =  sorted([find_advisory_date(f) for f in glob.glob('{}/{}-*'.format(data_dir, SUSE_FILE_PREFIX))]) 
        if flist:
            return flist[-1]


    logger.info('Suse Crawler started')

    latest_advisory_date = find_latest_suse_advisory_date(data_dir)
    if latest_advisory_date:
        logger.info('latest_suse_advisory_date={}'.format(latest_advisory_date.strftime(SUSE_DATE_MONTH_FORMAT)))
    else:
        logger.info('no centos advisories found. Downloading all')

    #try:
    #    response = requests.get(url)
    #except requests.exceptions.RequestException as e:
    #    logger.warn('Error while fetching package vulnerabilities: url={}, reason={}'.format(ubuntu_url, str(e)))
    #    return
    
    #soup = BeautifulSoup(response.text, "html.parser")
    with open('suse.html','r') as fp:
        content = fp.read()

    soup = BeautifulSoup(content, "html.parser")
    links = soup.find_all('a')
    for link in links:
        href = link.attrs.get('href')

        if href is None or not href.startswith('opensuse-security-announce-'):
            continue

        m = YEAR_MONTH_REGEX.match(href)
        if m:
            year, month = m.group(1), m.group(2)
            if int(year) < CUT_OFF_YEAR:
                logger.info('cut of year {} reached.'.format(CUT_OFF_YEAR))
                break
             current_advisory_date = datetime.strptime('{}-{}'.format(year,month), SUSE_DATE_FORMAT)
        else:
            logger.warn('expected pattern: year-month.txt[.gz]. found file name:{}'.format(href))
            continue

            url = '{}{}'.format(SUSE_URL, href)

    logger.info('Suse Crawler finished')

if __name__ == '__main__':

    format = '%(asctime)s %(levelname)s %(lineno)s %(funcName)s: %(message)s'
    formatter = logging.Formatter(format)
    
    logger = logging.getLogger("usncrawler")
    logger.setLevel(logging.DEBUG)
    
    log_file = 'ubuntu.log'
    fh = logging.handlers.RotatingFileHandler(log_file, maxBytes=2<<27, backupCount=4)
    fh.setFormatter(formatter)
    fh.setLevel(logging.INFO)
    logger.addHandler(fh)

    #urllib3.disable_warnings()
    data_dir='./sec_data/data'
    repo_dir='./sec_data/usnrepo'
    crawl_suse_advisories(logger, SUSE_URL, repo_dir, data_dir)
