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

    comp_id = "Linux.9-0-b"
    str_compliant = ""
    str_reason = ""

    packages_filename = prefix+"/__compliance_packages.txt"
    with open(packages_filename) as f:
        content = f.readlines()

    # Initialize
    str_compliant = "true"
    str_reason = "telnet server not found"

    for pkgline in content:
        pkgname = pkgline.strip().split()[0]
        if pkgname=="telnetd":
            version_info = ""
            if len(pkgline.strip().split())==2:
                version_info = " of version "+pkgline.strip().split()[1]
            str_compliant = "false"
            str_reason = "telnet server package, "+pkgname+version_info+", found. "
            break;

    for pkgline in content:
        pkgname = pkgline.strip().split()[0]
        if pkgname=="telnetd-ssl":
            version_info = ""
            if len(pkgline.strip().split())==2:
                version_info = " of version "+pkgline.strip().split()[1]
            str_compliant = "false"
            str_reason = str_reason + "telnet server package, "+pkgname+version_info+", found. " # str_reason is appended to the previous one
            break;

    outstr = "{\n"
    outstr = outstr + "\"compliance_id\":\""+comp_id+"\",\n"
    outstr = outstr + "\"description\":\""+DescriptionDict[comp_id]+"\",\n"
    outstr = outstr + "\"compliant\":\""+str_compliant+"\",\n"
    outstr = outstr + "\"reason\":\""+str_reason+"\",\n"
    outstr = outstr + "\"execution_status\":\""+StatusDict[ret_status]+"\",\n"
    outstr = outstr + "\"namespace\":\""+input_namespace+"\",\n"
    outstr = outstr + "\"crawled_time\":\""+input_tm+"\",\n"
    outstr = outstr + "\"compliance_check_time\":\""+datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")+"\",\n"
    outstr = outstr + "\"request_id\":\""+input_reqid+"\"\n"
    outstr = outstr + "}\n"

    print outstr
