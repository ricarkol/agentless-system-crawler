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

    input_namespace = sys.argv[1]
    input_tm = sys.argv[2]
    input_reqid = sys.argv[3]

    ret_status = 0
    prefix = GetUncrawlDirectoryName(input_namespace, input_tm)
    if prefix=="":
        ret_status = 4

    target_file = "/etc/profile"
    comp_id = "Linux.3-2-e"
    outstr = ""
    str_compliant = ""
    str_reason = ""
    # Check if /etc/profile exists.
    if not os.path.exists(prefix+target_file):
        str_compliant = "false"
        str_reason = "File "+target_file+" must exist."
    else:
        
        # If exists, it must have a line that invokes IBMsinit.sh
        found="false"
        after_text=[]
        with open(prefix+target_file, 'r') as fp:
            for line in fp:
                if ". /etc/profile.d/IBMsinit.sh" in line and line[0]=='.':
                    found="true"
                if found=="true":
                    after_text.append(line)

        if found=="false":
            str_compliant = "false"
            str_reason = "File "+target_file+" must call IBMsinit.sh."
        else:

            # And, umask should not be called after IBMsinit.sh is invoked.
            violation_found = "false"
            for line in after_text:
                if line.startswith("umask "):
                    violation_found = "true"

            if violation_found=="true":
                str_compliant = "false"
                str_reason = "Umask is set/reset after IBMsinit.sh is invoked."
            else:
                str_compliant = "true"
                str_reason = "File "+target_file+" calls IBMsinit.sh and umaks is not set/reset."

    if ret_status==4:
        str_compliant="unknown"
                    
    outstr = "{\n"
    outstr = outstr + "\"compliance_id\":\""+comp_id+"\",\n"
    outstr = outstr + "\"description\":\""+DescriptionDict[comp_id]+"\",\n"
    #current_command = "./comp."+comp_id+".sh "+prefix
    outstr = outstr + "\"compliant\":\""+str_compliant+"\",\n"
    outstr = outstr + "\"reason\":\""+str_reason+"\",\n"
    outstr = outstr + "\"execution_status\":\""+StatusDict[ret_status]+"\",\n"
    outstr = outstr + "\"namespace\":\""+input_namespace+"\",\n"
    outstr = outstr + "\"crawled_time\":\""+input_tm+"\",\n"
    outstr = outstr + "\"compliance_check_time\":\""+datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")+"\",\n"
    outstr = outstr + "\"request_id\":\""+input_reqid+"\"\n"
    outstr = outstr + "}\n"

    #EmitResultToCloudSight(outstr)
    print outstr
