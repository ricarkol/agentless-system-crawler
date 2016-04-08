#!/usr/bin/python

import os
import re
import sys
import json
import time
import urllib
import urllib2
import difflib
import datetime
import fileinput
import subprocess
from collections import defaultdict
import tempfile
from compliance_utils import *

#
# EXAMPLE OUTPUT
#
#  "/var/log/wtmp": {
#    "size": 0,
#    "feature_type": "file",
#    "uid": 0,
#    "key_hash": "88112de29bf70d11acd01d724acabf0b723b29d7",
#    "type": "file",
#    "ctime": 1423087328.496388,
#    "contents_hash": "da2d2176ca36ce7151aeca677b1399d270f47358",
#    "gid": 43,
#    "mode": 33204,
#    "mtime": 1422377121.0,
#    "path": "/var/log/wtmp",
#    "atime": 1423087328.496388,
#    "linksto": null,
#    "name": "wtmp"
#  },


if __name__ == '__main__':

    #prefix = tempfile.mkdtemp()

    input_namespace = sys.argv[1]
    input_tm = sys.argv[2]
    input_reqid = sys.argv[3]
    target_file_list = ["/etc/security/opasswd"]
    # Here, I first tried attaching "/" to the end of file name to force the os.makedirs to make it as a directory, not file.
    # But, if I do so, it fails to find an entry in the data returned from cloudsight.
    # So, I should not attach "/". Instead, I attach "/" after finding data from cloudsight using this path and before os.makedirs is called.
    # If os.makedirs sees a path ends with '/', it recognizes it as a directory and creates directory.

    ## Issue query to search service and make local copy of config files
    #ret_status = ReplicateFilesFromFileFeature(prefix, input_namespace, input_tm, target_file_list)
    ## No need to check if file exists. This compliance rule applies only if file exists.
    ##if ret_status==0:
    ##    ret_status = VerifyLocalFileExists(prefix, target_file_list)

    ret_status = 0
    prefix = GetUncrawlDirectoryName(input_namespace, input_tm)
    if prefix=="":
        ret_status = 4

    # Run script and store them to CloudSight
    outstr = CheckCompliance(prefix, "Linux.5-1-f", input_namespace, input_tm, input_reqid, ret_status)
    #EmitResultToCloudSight(outstr)
    print outstr
    #RemoveTempContent(prefix)
