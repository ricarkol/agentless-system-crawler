#!/usr/bin/env python2.7

from __future__ import print_function
import os
import sys
import time
import json
import pprint
import argparse
import datetime

import file_store
import get_usns_from_feed
import usn_index
import usndb


def parse_cmdline():
    parser = argparse.ArgumentParser(
            description="""Parse Ubuntu Security Notices (USN) atom feed
            and store individual usn info in ealstic search index and on local file system given by repo-dir""")
    parser.add_argument('--repo-dir', required=True, help='directory for redundant storage of individual ubunto security notices')
    return parser.parse_args()

def load_index_from_filerepo(args):
    try:
        return file_store.FileStore(args.repo_dir).get_all_usn()
    except Exception, e:
        print (e)

    print ('start usn save to elastic search', file=sys.stderr)
    usn_index.USNIndex(elastic_host=args.elastic_search).load_index(usn_info_list)
    print ('completed usn save to elastic search', file=sys.stderr)

def main():

    args = parse_cmdline()
    print('Arguments received from the command line', file=sys.stderr)
    pprint.pprint(vars(args), stream=sys.stderr)
    print(file=sys.stderr)
    usn_info_list = load_index_from_filerepo(args)
    distro_pkg_usn_map = usndb.process_usn_info(usn_info_list)
    #for tupleI in distro_pkg_usn_map:  
    #    print ('(dist,pkg)={}, fixes={}'.format(tupleI, distro_pkg_usn_map[tupleI]['pkgver'] ))

    #try:
#
#        usn_info_list = load_index_from_filerepo(args)
#        usndb.process_usn_info(usn_info_list)
#
#    except Exception, e:
#        print (e)
#        print (e, file=sys.stderr)

if __name__ == '__main__':

    main()
    
