#!/usr/bin/env python2.7

# Dump data from Ubuntu Security Notices for a particular vulnerability
# into JSON format.
# 
# An example of a USN information page is here:
# http://www.ubuntu.com/usn/usn-2126-1/

import re
import pprint
import argparse
import logging
import requests
import json
from bs4 import BeautifulSoup
import os

assert (requests.__version__ >= '2.2.1')

def cmdline():
    parser = argparse.ArgumentParser(description='Get Ubuntu Security Notice data')
    parser.add_argument('--usn', required=True, nargs='+',
            help='the ID of the notice')
    return parser.parse_args()

class UsnToJson:
    @classmethod
    def extractFixDataFromSoup(klass, soup):
        """
        Extract relevant data from the html page of the USN.

        Returns a list of lists, one for each distro version. The list for
        a distro version consists of the information about the distro at
        position 0 in the list. Positions 1, 2, ... contain package
        information for that distro version.
        """
        #print soup
        #print '-' * 80
        group = []
        for i in soup.dl.find_all(['dt', 'dd']):
            if i.name == 'dt':
                if group: yield group
                group = []
            group.append(i)
        if group: yield group

    @classmethod
    def ubuntuVersionCodeName(klass, distroversion):
        mapping = {
            '13.10': 'saucy',
            '12.10': 'quantal',
            '12.04': 'precise',
            '10.04': 'lucid',
            '14.04': 'trusty',
            '14.10': 'utopic',
            '15.04': 'vivid',
            '15.10': 'wily',
        }
        for (k, v) in mapping.iteritems():
            if k in distroversion:
                return v
        return distroversion

    @classmethod
    def distroInfoToDict(klass, distroinfo):
        distro = distroinfo[0]
        packages = distroinfo[1:]
        _packages = []
        for pkg in packages:
            if pkg.a:
                _packages.append({ 'name': pkg.a.contents[0],
                                  'version': pkg.span.a.contents[0],
                                  'release': '' })
            else:
                _packages.append({ 'name': pkg.contents[0],
                                  'version': pkg.span.contents[0],
                                  'release': '' })

        return {
                'os': { 'name': 'ubuntu', 'version': klass.ubuntuVersionCodeName(distro.contents[0]), "distribution":"", "architecture": ""},
            'packages': _packages
        }

    @classmethod
    def usnSummaryFromSoup(klass, soup):
        for h3 in soup.find_all('h3'):
            contents = h3.contents
            if isinstance(contents, list) and contents[0] == 'Summary':
                summary = h3.find_next_sibling('p').contents[0]
                return re.sub(r'\s', r' ', summary)
        return ''

    @classmethod
    def parseUSN(klass, usn, data_dir, save_data, logger):
        """
        """
        url = 'http://www.ubuntu.com/usn/%s/' % usn
        fname = os.path.join(data_dir, usn)
        if os.path.exists(fname):
            return
        r = requests.get(url)
        logger.info('downloading:{}'.format(url))
        html = r.text
        # record file, save content if enabled
        with open(os.path.join(data_dir, usn),'w') as wp:
            if save_data:
                wp.write(html.encode('utf-8'))
        soup = BeautifulSoup(html, "html.parser")
        fixdata = [ klass.distroInfoToDict(distroinfo)
            for distroinfo in klass.extractFixDataFromSoup(soup) ]
        return {
            'site': url,
            'id': usn,
            'summary': klass.usnSummaryFromSoup(soup),
            'fixes': fixdata,
        }

def main():
    logging.basicConfig(level=logging.DEBUG)
    args = cmdline()
    usninfos = [ UsnToJson.parseUSN(u) for u in args.usn ]
    print json.dumps(usninfos, indent=2)

if __name__ == '__main__':
    main()
