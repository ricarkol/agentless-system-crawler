
import os
import gzip
import rpm
from rpmUtils.miscutils import splitFilename
import requests
from bs4 import BeautifulSoup
import zlib
import urllib3
import json
import re
import logging
import logging.handlers
from datetime import datetime

#CENTOS_URL='https://lists.centos.org/pipermail/centos-announce/'
#REPO_DIR='./usnrepo'
year_month_regex=re.compile('(\d+)-(\w+)\.txt.*')
CENTOS_FNAME_PREFIX = 'centos-'
CENTOS_DATE_FORMAT = '%Y-%B'

CUT_OFF_YEAR = 2010   # prior year advisories will not be used

def update_rhsa_advisory(logger, repo_dir, centos_advisory_updates):
    
    for advisory_file, advisory_fixes in centos_advisory_updates.iteritems():
        fname = os.path.join(repo_dir, advisory_file)
        if not os.path.exists(fname):
            logger.info('{} does not exist'.format(fname))
            continue
    
        logger.info('updating {}'.format(fname))
        with open(fname, 'r') as rp:
           adv_json = json.load(rp)
           if not ('fixes' in adv_json and adv_json['fixes']):
               continue
    
        for fix in adv_json['fixes']: 
            try:
                if fix['os']['name'] != 'centos':
                    continue
                for fix_pkg in fix['packages']:
                    ver_rel = advisory_fixes.get(fix_pkg['name'])
                    if ver_rel:
                        fix_pkg['version'] = ver_rel[0]
                        fix_pkg['release'] = ver_rel[1]
                        fix_pkg['fqn'] = '{}-{}-{}'.format(fix_pkg['name'], ver_rel[0], ver_rel[1])
    
            except KeyError, e:
                logger.error (e)
                logger.exception(e)
                    
        with open(fname, 'w') as wp:
           json.dump(adv_json, wp, indent=2)

def process_centos_advisory(advisory_data):
    centos_advisory_update = {}
    lines = advisory_data.split('\n')
    current_rhsa = None
    collect = False
    for line in lines:
        #line = line.strip()
        if 'https://rhn.redhat.com/errata/RHSA' in line:
            current_rhsa = line[line.index('RHSA'):line.rindex('.')]
            # in Red Hat advisory the name convention is RHSA-2012:0973
            # in centos advisory same this is referred to as RHSA-2012-0973
            parts = current_rhsa.split('-')
            current_rhsa = '{}-{}:{}'.format(parts[0], parts[1], parts[2])
            continue
        if (line.startswith('x86_64:')  or line.startswith('/updates/x86_64')) and current_rhsa:
            collect = True
            continue
        if collect:
            if line:
                #advisory in 2005
                #  x86_64:
                #  updates/x86_64/RPMS/gtk2-2.2.4-15.i386.rpm
                #  updates/x86_64/RPMS/gtk2-2.2.4-15.x86_64.rpm
                #  updates/x86_64/RPMS/gtk2-devel-2.2.4-15.x86_64.rpm

                # advisory in 2012
                # x86_64:
                # 9a51f3a313b84b021dfae9da9356da939f0d98c88bc6bb22f7ddba5f2f465b6c  device-mapper-multipath-0.4.7-48.el5_8.1.x86_64.rpm
                # d6ba1caaf305ec296475d9455ed63104319d523757937da72c4334cd282a0ef0  kpartx-0.4.7-48.el5_8.1.x86_64.rpm
                #
                line_parts = line.split()
                if len(line_parts) == 2:
                    pkg = line_parts[1]
                elif len(line_parts) == 1:
                    pkg = line_parts[0]

                if pkg.startswith('updates/x86_64/RPMS/'):
                    pkg = pkg[len('updates/x86_64/RPMS/'):]
                elif pkg.startswith('updates/s390/RPMS'):  # data seems to be incorrect see 2006-March.txt.gz
                    continue
                # some of the packages end with : like kernel-doc-2.6.9-11.EL.noarch.rpm:
                if pkg.endswith(':'):
                    pkg = pkg[:-1]
                (name, ver, rel, epoch, arch) = splitFilename(pkg)
                combined = '{} {} {}-{}'.format(current_rhsa, name, ver, rel)
                if len(combined.split()) !=3:
                    logger.warn('problem parsing: {}'.format(combined))
                if current_rhsa in centos_advisory_update:
                    centos_advisory_update[current_rhsa][name] = [ver, rel]
                else:
                    centos_advisory_update[current_rhsa] = {name: [ver, rel]}
            else:
                collect = False
                current_rhsa = None 

    return centos_advisory_update
                

def crawl_centos_advisories(logger, centos_url, repo_dir, data_dir, save_data=False):
    
    def find_advisory_date(advisory_fname):
        sp = advisory_fname.split('-')
        return datetime.strptime('{}-{}'.format(sp[1],sp[2].split('.')[0]), CENTOS_DATE_FORMAT)

    def find_latest_centos_advisory_date(data_dir):
        import glob
        flist =  sorted([find_advisory_date(f) for f in glob.glob('{}/{}*'.format(data_dir, CENTOS_FNAME_PREFIX))]) 
        if flist:
            return flist[-1]

    logger.info('Centos Crawler started')
    latest_advisory_date = find_latest_centos_advisory_date(data_dir)
    if latest_advisory_date:
        logger.info('latest_centos_advisory_date={}'.format(latest_advisory_date.strftime(CENTOS_DATE_FORMAT)))
    else:
        logger.info('no centos advisories found. Downloading all')

    try:
        response = requests.get(centos_url)
    except requests.exceptions.RequestException as e:
        logger.warn('Error while fetching package vulnerabilities:url={}, reason={}'.format(centos_url,str(e)))
        return

    soup = BeautifulSoup(response.text, "html.parser")
    links = soup.find_all('a')

    for link in links:
        href = link['href']
        if href.endswith('.gz'):
            url = '{}{}'.format( centos_url,href)

            m = year_month_regex.match(href)
            if m:
                year = m.group(1)
                month = m.group(2)
                current_advisory_date = datetime.strptime('{}-{}'.format(year,month), CENTOS_DATE_FORMAT)
            else:
                logger.warn('expected pattern: year-month.txt[.gz]. found file name:{}'.format(href))
                continue

            if int(year) < CUT_OFF_YEAR:
                break # we have fetched all we need to

            if latest_advisory_date and current_advisory_date < latest_advisory_date:
                break # we have fetched all we need to

            fname = os.path.join(data_dir, '{}{}'.format( CENTOS_FNAME_PREFIX, href))
            logger.info('downloading:{}'.format(fname))

            try:
                response = requests.get(url)
            except requests.exceptions.RequestException as e:
                logger.warn('Error while fetching package vulnerabilities:url={}, reason={}'.format(url,str(r)))
                continue
            response = requests.get(url)

            # record file, save content if enabled
            with open(fname, 'wb') as fp:
                if save_data:
                    fp.write(response.content)
                    
            # see http://stackoverflow.com/questions/1838699/how-can-i-decompress-a-gzip-stream-with-zlib
            decompressed_data = zlib.decompress(response.content, 15 + 32)
            centos_advisory_updates = process_centos_advisory(decompressed_data)
            update_rhsa_advisory(logger, repo_dir, centos_advisory_updates)

    logger.info('CentOs Crawler finished')

if __name__ == '__main__':
    urllib3.disable_warnings()
    format = '%(asctime)s %(levelname)s %(lineno)s %(funcName)s: %(message)s'
    formatter = logging.Formatter(format)
    
    logger = logging.getLogger("usncrawler")
    logger.setLevel(logging.DEBUG)
    
    log_file = 'centos.log'
    fh = logging.handlers.RotatingFileHandler(log_file, maxBytes=2<<27, backupCount=4)
    fh.setFormatter(formatter)
    fh.setLevel(logging.INFO)
    logger.addHandler(fh)

    centos_url='https://lists.centos.org/pipermail/centos-announce/'

    repo_dir='./sec_data/usnrepo'
    data_dir='./sec_data/data'
    crawl_centos_advisories(logger, centos_url, repo_dir, data_dir)
