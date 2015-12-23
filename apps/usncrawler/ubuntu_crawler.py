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

UBUNTU_URL='https://lists.ubuntu.com/archives/ubuntu-security-announce/'
#REPO_DIR='./usnrepo'
USN_SIG='Ubuntu Security Notice'
USN_SIG_LEN = len(USN_SIG)
SUMMARY='Summary:'
DESCRIPTION='Software Description:'
UPDATE_INSTRUCTIONS='Update instructions'
REFERENCES='References:'

CUT_OFF_YEAR = 2012   # prior year advisories will not be used

PACKAGE_ATTRIB = ['name','version','release']
year_month_regex=re.compile('(\d+)-(\w+)\.txt.*')

# we need to get the automatically from https://wiki.ubuntu.com/DevelopmentCodeNames
UBUNTU_RELEASE_MAP = {
    '6.06': 'dapper',
    '7.04': 'feisty',
    '8.04': 'hardy',
    '9.04': 'jaunty',
    '10.04': 'lucid',
    '10.10': 'maverick',
    '11.04': 'natty',
    '11.10': 'oneiric',
    '12.04': 'precise',
    '12.10': 'quantal',
    '13.04': 'raring',
    '13.10': 'saucy',
    '14.04': 'trusty',
    '14.10': 'utopic',
    '15.04': 'vivid',
    '15.10': 'wily'
}

# example: 'For the stable distribution (wheezy), this problem has been fixed in version 2.0.19-stable-3+deb7u1.'
dist_ver_regex = re.compile('.*\((\w+)\).*\sversion\s(\S+)\.$')

def process_security_message(logger, lines, size, repo_dir, data_dir):

    def find_usn_id_release_date(lines, size):
        for idx in xrange(size):
            line = lines[idx]
            if line.startswith('Ubuntu Security Notice'):
                usn_id = line[USN_SIG_LEN:].strip().lower()
                release_date = datetime.strptime(lines[idx+1].strip(),'%B %d, %Y').strftime('%Y-%m-%d')
                return usn_id, release_date
        return None, None

    def find_summary(lines, size):
        summary = []
        begin = False
        for idx in xrange(size):
            line = lines[idx]
            if line.startswith('Summary:'):
                begin = True
                continue
            if begin:
                if line.startswith('Software Description:'):
                    break
                else:
                    if len(line.strip()) == 0:
                        continue
                    else:
                        summary.append(line)

        return ''.join(summary)

    def find_fixes(lines, size, id, release_date, summary):
        fixes = []
        begin_packages = False
        begin_ref = False
        os_ver = None
        packages = []
        cveids = []
        url = None
        for idx in xrange(size):
            line = lines[idx]
            if line.startswith('Update instructions:'):
                begin_packages = True
                continue
            if begin_packages and line.startswith('Ubuntu '):
                os_ver = UBUNTU_RELEASE_MAP.get(line.strip()[:-1].split()[1])
                continue
            if os_ver:
                if len(line.strip()) != 0:
                    d = dict(map(None,PACKAGE_ATTRIB,line.strip().split()))
                    d['release']=''
                    packages.append(d)
                else:
                    fixes.append({
                        'os': { 'name':'ubuntu', 'version': os_ver, 'distribution': '', 'architecture': ''}, 
                        'packages' : packages 
                        })
                    os_ver=None
                    packages = []
            if line.startswith('References:'):
                begin_packages = False
                begin_ref = True
                continue
            if begin_ref:
                if 'http://www.ubuntu.com/usn' in line: 
                    url = line.strip()
                elif len(line.strip()) == 0:
                    break
                else:
                    cveids.extend([ q for q in [ p.strip() for p in line.split(',') if len(p.strip()) > 0] if q.startswith('CVE-')])

        # sometimes advisories contain multiple references, while the link we form
        # below always takes to the USN which can guide the user correctly
        url = 'http://www.ubuntu.com/usn/{}'.format(id)
        return {
           'id': id, 'site': url, 'releasedate': release_date, 'category':'security',
           'cveid': cveids, 'fixes': fixes, 'vendor': 'ubuntu', 'summary': summary} 


        
    id, release_date = find_usn_id_release_date(lines, size)
    summary = find_summary(lines, size)
    return find_fixes(lines, size, id, release_date, summary)


def crawl_ubuntu_advisories(logger, ubuntu_url, repo_dir, data_dir, save_data=False):
    '''
    crawls ubuntu security advisory
    compares the latest file in data dir, fetches only newer data
    '''
    
    def find_advisory_date(advisory_fname):
        sp = advisory_fname.split('-')
        return datetime.strptime('{}-{}'.format(sp[1],sp[2].split('.')[0]), '%Y-%B')

    def find_latest_ubuntu_advisory_date(data_dir):
        import glob
        flist =  sorted([find_advisory_date(f) for f in glob.glob('{}/ubuntu-*'.format(data_dir))]) 
        if flist:
            return flist[-1]

    def find_next_message(lines, start):
        begin = None
        for i in xrange(start, len(lines)):
            line = lines[i]
            if begin:
                if line.startswith('-------------- next part --------------'):
                    return begin, i
            else:
                if line.startswith('=======================') or line.startswith('1====================') :
                    begin = i
        return None, None

    logger.info('Ubuntu Crawler started')
    latest_advisory_date = find_latest_ubuntu_advisory_date(data_dir)
    if latest_advisory_date:
        logger.info('latest_ubuntu_advisory_date={}'.format(latest_advisory_date.strftime('%Y-%B')))
    else:
        logger.info('no ubuntu advisories found. Downloading all')

    try:
        response = requests.get(ubuntu_url)
    except requests.exceptions.RequestException as e:
        logger.warn('Error while fetching package vulnerabilities: url={}, reason={}'.format(ubuntu_url, str(e)))
        return

    soup = BeautifulSoup(response.text, "html.parser")
    links = soup.find_all('a')
    for link in links:
        href = link['href']

        if not (href.endswith('.txt') or href.endswith('.txt.gz')):
            continue

        m = year_month_regex.match(href)
        if m:
            year = m.group(1)
            month = m.group(2)
            current_advisory_date = datetime.strptime('{}-{}'.format(year,month), '%Y-%B')
        else:
            logger.warn('expected pattern: year-month.txt[.gz]. found file name:{}'.format(href))
            continue

        if int(year) < CUT_OFF_YEAR:
            break # we have fetched all we need to

        if latest_advisory_date and current_advisory_date < latest_advisory_date:
            break # we have fetched all we need to

        url = '{}{}'.format( ubuntu_url,href)
        fname = os.path.join(data_dir, 'ubuntu-{}'.format(href))
        logger.info('downloading:{}'.format(fname))

        try:
            response = requests.get(url)
        except requests.exceptions.RequestException as e:
            logger.warn('Error while fetching package vulnerabilities:url={}, reason={}'.format(url,str(e)))
            continue

        # record file, save content if enabled
        with open(fname, 'wb') as fp:
            if save_data:
                fp.write(response.content)

        if href.endswith('.txt.gz'):
            # see http://stackoverflow.com/questions/1838699/how-can-i-decompress-a-gzip-stream-with-zlib
            lines = zlib.decompress(response.content, 15 + 32).split('\n')
        else:
            lines = response.content.split('\n')

        begin, end = find_next_message(lines, 0)
        while begin:
            logger.debug('begin={}, end={}'.format(begin, end))
            msg = process_security_message(logger=logger, lines=lines[begin:end], size=end-begin, data_dir=data_dir, repo_dir=repo_dir)
            if msg['id'] is None:
                logger.error('usn id is none. usn={}'.format(msg))
            rname = os.path.join(repo_dir, msg['id'].lower())
            logger.info('adding {}'.format(msg['id'].lower()))
            with open(rname, 'w') as fp:
               fp.write(json.dumps(msg, indent=2)) 
            begin, end = find_next_message(lines, end)

    logger.info('Ubuntu Crawler finished')

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
    crawl_ubuntu_advisories(logger, UBUNTU_URL, repo_dir, data_dir)
