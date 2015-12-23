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

if __name__ == '__main__':

    #prefix = tempfile.mkdtemp()

    input_namespace = sys.argv[1]
    input_tm = sys.argv[2]
    input_reqid = sys.argv[3]
    target_file_list = ["/etc/login.defs", "/etc/shadow"]

    # Issue query to search service and make local copy of config files
    #ret_status = ReplicateFilesFromConfigFeature(prefix, input_namespace, input_tm, target_file_list)
    #if ret_status==0:
    #    ret_status = VerifyLocalFileExists(prefix, target_file_list)

    ret_status = 0
    prefix = GetUncrawlDirectoryName(input_namespace, input_tm)
    if prefix=="":
        ret_status = 4

    # Run script and store them to CloudSight
    outstr = CheckCompliance(prefix, "Linux.2-1-b", input_namespace, input_tm, input_reqid, ret_status)
    #EmitResultToCloudSight(outstr)
    print outstr
    #RemoveTempContent(prefix)
