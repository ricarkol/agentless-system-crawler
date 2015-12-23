
import os
import requests
from bs4 import BeautifulSoup
import zlib
import urllib3
import json
import logging
import logging.handlers
import re
import glob
import string

DEBIAN_URL='https://lists.debian.org/debian-security-announce/'
#REPO_DIR='./usnrepo'
DSA_SIG='Debian Security Advisory'
DSA_SIG_LEN = len(DSA_SIG)
DSA_MAIL='security@debian.org'
DSA_MAIL_LEN=len(DSA_MAIL)
YEARS_SUPPORTED=['2015', '2014', '2013', '2012', '2011']

# example: 'For the stable distribution (wheezy), this problem has been fixed in version 2.0.19-stable-3+deb7u1.'
dist_ver_regex = re.compile('.*\((\w+)\).*\sversion\s(\S+)\.$')

def dsa_to_json(logger, data_file, repo_dir, data_dir):

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

    def file_to_url(data_file):
        url_prefix='https://lists.debian.org/debian-security-announce'
        file_part = os.path.basename(data_file)[4:]
        file_part = string.replace(file_part, '-','/')
        return '{}/{}'.format(url_prefix, file_part)

    ############################################################
    # patch schema: elements tagged with * are mandatory
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
    #       name* (rhel)
    #       version* (7.0)
    #       architecture (32-bit)
    #       distribution (server)
    #     packages[]*
    #       name*
    #       version*
    #       release
    #       architecture
    ############################################################

    with open(data_file, 'r') as fp:
        day_soup = BeautifulSoup(fp.read(), "html.parser")
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
             'site': file_to_url(data_file),
             'cveid': cveid,
             'category': 'security',
             'summary':summary,
             'fixes': fixes
            }

            with open(os.path.join(repo_dir, dsa_id), 'w') as wp:
                wp.write(json.dumps(sec_adv, indent=2))


def crawl_debian_repo(logger, repo_dir, data_dir):
    
    logger.info('Debian Loader starts')
    flist = glob.glob('{}/deb-*'.format(data_dir))
    flist.sort()
    for fname in flist:
        print fname
        dsa_to_json(logger, fname, repo_dir, data_dir)

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

    #urllib3.disable_warnings()
    data_dir='./data'
    repo_dir='./junk'
    crawl_debian_repo(logger, repo_dir, data_dir)
