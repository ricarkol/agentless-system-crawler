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
# "/etc/pam.d/sshd": {
#   "contents_hash": "47fdddcc665b18142b17cd31298a40f2c27693ef",
#   "name": "sshd",
#   "key_hash": "877d51ccb0b62fab0f9248ff27c073c7233aba0e",
#   "content": "# PAM configuration for the Secure Shell service\n\n# Read environment pam_selinux.so multiple\n\n# Standard Un*x password\n",
#   "path": "/etc/pam.d/sshd",
#   "feature_type": "config"
# },


if __name__ == '__main__':

    #prefix = tempfile.mkdtemp()

    input_namespace = sys.argv[1]
    input_tm = sys.argv[2]
    input_reqid = sys.argv[3]
    target_file_list = ["/etc/pam.d/rlogin","/etc/pam.d/rsh","/lib/security/pam_rhosts_auth.so"]

    # Issue query to search service and make local copy of config files
    #ret_status = ReplicateFilesFromFileFeature(prefix, input_namespace, input_tm, target_file_list)
    #ret_status = ReplicateFilesFromConfigFeature(prefix, input_namespace, input_tm, target_file_list)
    ##if ret_status==0:
    ##    ret_status = VerifyLocalFileExists(prefix, target_file_list)

    ret_status = 0
    prefix = GetUncrawlDirectoryName(input_namespace, input_tm)
    if prefix=="":
        ret_status = 4

    # Run script and store them to CloudSight
    outstr = CheckCompliance(prefix, "Linux.8-0-o", input_namespace, input_tm, input_reqid, ret_status)
    #EmitResultToCloudSight(outstr)
    print outstr
    #RemoveTempContent(prefix)
