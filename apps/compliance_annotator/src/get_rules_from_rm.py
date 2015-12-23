#!/usr/bin/python

import os
import re
import sys
import json
import time
import pickle
import fileinput
import subprocess
import urllib
import urllib2
import datetime
import calendar
import ConfigParser
import stat
from collections import defaultdict
from kafka import KafkaClient, SimpleProducer, KeyedProducer
from urllib2 import Request, urlopen, URLError
import difflib
from compliance_utils import *

if __name__ == '__main__':

    cmd = 'curl -s -k -XGET https://kasa.sl.cloud9.ibm.com:9292/api/get_rules?namespace=xxxx'
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret=="":
        print "No compliance rules are available. using default ..."

    print ret

    cmp_data = []
    if ret != "":
        cmp_data = json.loads(ret)

    print cmp_data
