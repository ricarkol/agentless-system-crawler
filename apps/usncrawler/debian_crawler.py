
import os
import requests
from bs4 import BeautifulSoup
import zlib
import urllib3
import json
import logging
import logging.handlers
import re

DEBIAN_URL='https://lists.debian.org/debian-security-announce/'
#REPO_DIR='./usnrepo'
DSA_SIG='Debian Security Advisory'
DSA_SIG_LEN = len(DSA_SIG)
DSA_MAIL='security@debian.org'
DSA_MAIL_LEN=len(DSA_MAIL)

CUT_OFF_YEAR = 2010   # prior year advisories will not be used

# example: 'For the stable distribution (wheezy), this problem has been fixed in version 2.0.19-stable-3+deb7u1.'
dist_ver_regex = re.compile('.*\((\w+)\).*\sversion\s(\S+)\.$')

def handle_yearly_archive(logger, debian_url, year_url, year, repo_dir, data_dir, latest_dsa_file, save_data):

    def find_dsa_id(lines):
        for line in lines:
            if line.startswith('Debian Security Advisory'):
                return line[DSA_SIG_LEN:-DSA_MAIL_LEN].strip()

    def find_package(lines):
        for line in lines:
            if line.startswith('Package'):
                return line.split(':')[1].strip()

    def find_cve_and_summary(lines):
        cves = []
        summary = ''
        sl = []
        cve_begin = -1
        cve_end = -1
        summary_end = -1
        for idx in xrange(len(lines)):
            line = lines[idx]
            if line.startswith('CVE ID'):
                cve_begin = idx
                cves.extend(line.split(':')[1].strip().split())
                continue
            if cve_begin > 0:
                if cve_end < 0:
                    if len(line.strip()) == 0:
                        cve_end = idx
                        continue
                    else:
                        if not line.startswith('Debian'):
                            cves.extend(line.strip().split())
                else:
                    if len(line.strip())!=0:
                        sl.append(line)
                    else:
                        break

        summary = '\n'.join(sl)
        return cves, summary

    def find_distribution_version(lines):
        dlines = []
        dist_ver = []
        for idx in xrange(len(lines)):
            if 'distribution' in lines[idx]:
                dlines.append(lines[idx]+' '+lines[idx+1])
        for line in dlines:
            if 'distribution' in line and 'fixed' in line and 'version' in line:
                m=dist_ver_regex.match(line)
                if m:
                    dist_ver.append((m.group(1), m.group(2)))

        return dist_ver

    # -------------- handle_yearly_archive  begin ------------
    try:
        response = requests.get(year_url)
    except requests.exceptions.RequestException as e:
        logger.warn('Error while fetching package vulnerabilities:url={}, reason={}'.format(year_url,str(e)))
        return

    soup = BeautifulSoup(response.text, "html.parser")
    links = soup.find_all('a')

    for link in links:
        href = link['href']

        if href.startswith('msg') and href.endswith('.html'):

            data_file_name = '{}/deb-{}-{}'.format(data_dir, year,href)

            if latest_dsa_file and data_file_name < latest_dsa_file:
                continue

            url = '{}{}/{}'.format( debian_url,year, href)
            logger.info('downloading {}, latest_dsa_file:{}'.format(url, latest_dsa_file))
            try:
                response = requests.get(url)
            except requests.exceptions.RequestException as e:
                logger.warn('Error while fetching package vulnerabilities:url={}, reason={}'.format(url,str(e)))
                continue

            # record file name, save content if enabled
            with open(data_file_name, 'w') as wp:
                if save_data:
                    wp.write(response.text)

            day_soup = BeautifulSoup(response.text, "html.parser")
            pres = day_soup.find_all('pre')

            for pre in pres:
                lines = pre.text.split('\n')
                dsa_id = find_dsa_id(lines)
                pkg = find_package(lines)
                cveid, summary = find_cve_and_summary(lines)
                dist_ver = find_distribution_version(lines)

                fixes = []
                for dist, ver in dist_ver:
                    f = { 
                        'os': { 'name': 'debian', 'version': dist, 'architecture':'', 'distribution':''},
                        'packages':[ {'name': pkg, 'version': ver, 'release': ''}]
                    }
                    fixes.append(f)

                sec_adv = {
                 'id' : dsa_id,
                 'site': url,
                 'cveid': cveid,
                 'category': 'security',
                 'summary':summary,
                 'fixes': fixes
                }

                with open(os.path.join(repo_dir, dsa_id), 'w') as wp:
                    wp.write(json.dumps(sec_adv, indent=2))


def crawl_debian_advisories(logger, debian_url, repo_dir, data_dir, save_data=False):
    
    def find_latest_deb_advisory(data_dir):
        import glob
        flist = glob.glob('{}/deb-*'.format(data_dir))
        flist.sort()
        if flist:
            return flist[-1]

    logger.info('Debian Crawler started')
    dl = len('debian-security-announce-')
    try:
        response = requests.get(debian_url)
    except requests.exceptions.RequestException as e:
        logger.warn('Error while fetching package vulnerabilities:url={}, reason={}'.format(debian_url,str(e)))
        return

    soup = BeautifulSoup(response.text, "html.parser")
    links = soup.find_all('a')

    latest_deb_advisory = find_latest_deb_advisory(data_dir)
    for link in links:
        href = link['href']
        if href.startswith('debian-security-announce-'):
            year = href[dl:dl+4]

            if int(year) <= CUT_OFF_YEAR:
               continue # debian lists are in chronological order

            url = '{}/{}'.format( debian_url,href)
            handle_yearly_archive(logger, debian_url, url, year, repo_dir, data_dir, latest_deb_advisory, save_data)

    logger.info('Debian Crawler finished')

if __name__ == '__main__':

    format = '%(asctime)s %(levelname)s %(lineno)s %(funcName)s: %(message)s'
    formatter = logging.Formatter(format)
    
    logger = logging.getLogger("usncrawler")
    logger.setLevel(logging.DEBUG)
    
    log_file = 'debian.log'
    fh = logging.handlers.RotatingFileHandler(log_file, maxBytes=2<<27, backupCount=4)
    fh.setFormatter(formatter)
    fh.setLevel(logging.INFO)
    logger.addHandler(fh)

    urllib3.disable_warnings()
    data_dir='./sec_data/data'
    repo_dir='./sec_data/usnrepo'
    crawl_debian_advisories(logger, DEBIAN_URL, repo_dir, data_dir)
