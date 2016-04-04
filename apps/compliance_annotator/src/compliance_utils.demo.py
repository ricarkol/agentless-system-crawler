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
import difflib
import datetime
import calendar
import ConfigParser
import stat
from collections import defaultdict
from kafka import KafkaClient, SimpleProducer, KeyedProducer
from urllib2 import Request, urlopen, URLError
import uuid

###############################################################
# CONFIGURATION
###############################################################


# demo3 environment
myserver_domain_name="r2d2.sl.cloud9.ibm.com"
kafka_group_id="compliance-annotator-r2d2"
search_service_ip_port="demo3.sl.cloud9.ibm.com:8885"
kafka_ip_port="demo3.sl.cloud9.ibm.com:9092"
elasticsearch_ip_port="demo3.sl.cloud9.ibm.com:9200"

# cloudsight environment
#myserver_domain_name="9.2.219.141"
#kafka_group_id="compliance-annotator"
#search_service_ip_port="cloudsight.sl.cloud9.ibm.com:8885"
#kafka_ip_port="kafka-cs.sl.cloud9.ibm.com:9092"
#elasticsearch_ip_port="elastic2-cs.sl.cloud9.ibm.com:9200"

# watson environment
#search_service_ip_port="10.26.77.191:8885"
#kafka_ip_port="10.109.223.165:9092"

crawl_annotation_report_delay=5 # for report.html generation only, without using search service


###############################################################


compliance_rule_list = [
    "Linux.1-1-a",
    "Linux.2-1-b",
#    "Linux.2-1-c",
    "Linux.2-1-d",
#    "Linux.2-1-e",
    "Linux.3-1-a",
#    "Linux.3-2-b",
###    "Linux.3-2-e",
###    "Linux.3-2-f",
    "Linux.5-1-a",
    "Linux.5-1-b",
    "Linux.5-1-d",
    "Linux.5-1-e",
    "Linux.5-1-f",
#    "Linux.5-1-g",
#    "Linux.5-1-h",
#    "Linux.5-1-i",
    "Linux.5-1-j",
    "Linux.5-1-k",
    "Linux.5-1-l",
    "Linux.5-1-m",
    "Linux.5-1-n",
#    "Linux.5-1-o",
#    "Linux.5-1-p",
#    "Linux.5-1-q",
#    "Linux.5-1-r",
    "Linux.5-1-s",
#    "Linux.5-2-c",
#    "Linux.5-2-d",
#    "Linux.6-1-a",
#    "Linux.6-1-b",
#    "Linux.6-1-c",
    "Linux.6-1-d",
    "Linux.6-1-e",
    "Linux.6-1-f",
#    "Linux.6-1-g",
    "Linux.8-0-o",
#    "Linux.8-0-u",
#    "Linux.8-0-v",
#    "Linux.8-0-w"
]


StatusDict = {
    0: "Success",
    1: "Feature data not available.",
    2: "Search service not reachable.",
    3: "Required file or directory missing.",
    4: "Uncrawled data unavailable."
}

DescriptionDict = {
    "Linux.1-1-a": "UID must be used only once",
    "Linux.2-1-b": "Maximum password age",
    "Linux.2-1-c": "Minimum password length",
    "Linux.2-1-d": "Minimum days before password change",
    "Linux.2-1-e": "Prevent password reuse",
    "Linux.3-1-a": "motd file checking",
    "Linux.3-2-b": "UMASK value 077 in /etc/login.defs",
    "Linux.3-2-e": "/etc/profile",
    "Linux.3-2-f": "/etc/csh.login",
    "Linux.5-1-a": "Read/write access of ~root/.rhosts only by root",
    "Linux.5-1-b": "Read/write access of ~root/.netrc only by root",
    "Linux.5-1-d": "Permission check of /usr",
    "Linux.5-1-e": "Permission check of /etc",
    "Linux.5-1-f": "Permission check of /etc/security/opasswd",
    "Linux.5-1-g": "Permission check of /etc/shadow",
    "Linux.5-1-h": "Permission check of /etc/profile.d/IBMsinit.sh",
    "Linux.5-1-i": "Permission check of /etc/profile.d/IBMsinit.sh",
    "Linux.5-1-j": "Permission check of /var",
    "Linux.5-1-k": "Permission check of /var/tmp",
    "Linux.5-1-l": "Permission check of /var/log",
    "Linux.5-1-m": "Permission check of /var/log/faillog",
    "Linux.5-1-n": "Permission check of /var/log/tallylog",
    "Linux.5-1-o": "Permission check of /var/log/syslog or /var/log/messages",
    "Linux.5-1-p": "Permission check of /var/log/wtmp",
    "Linux.5-1-q": "Permission check of /var/log/auth.log or /var/log/secure",
    "Linux.5-1-r": "Permission check of /tmp",
    "Linux.5-1-s": "Permission check of snmpd.conf",
    "Linux.5-2-c": "Enforce default no access policy",
    "Linux.5-2-d": "ftp access restriction",
    "Linux.6-1-a": "syslog file checking",
    "Linux.6-1-b": "messages file checking",
    "Linux.6-1-c": "syslog file checking",
    "Linux.6-1-d": "wtmp file checking",
    "Linux.6-1-e": "faillog file checking",
    "Linux.6-1-f": "tallylog file checking",
    "Linux.6-1-g": "secure or auth file checking",
    "Linux.8-0-o": "no_hosts_equiv must be present",
    "Linux.8-0-u": "net.ipv4.tcp_syncookies =1",
    "Linux.8-0-v": "net.ipv4.icmp_echo_ignore_broadcasts = 1",
    "Linux.8-0-w": "net.ipv4.conf.all.accept_redirects = 0",
}


#btime="2015-04-23T01:01:01Z"
#etime="2015-04-25T05:50:01Z"
btime=(datetime.datetime.utcnow()-datetime.timedelta(minutes=10)).strftime("%Y-%m-%dT%H:%M:%SZ")
etime=(datetime.datetime.utcnow()+datetime.timedelta(minutes=1)).strftime("%Y-%m-%dT%H:%M:%SZ")

def GetUncrawlDirectoryName(in_namespace, in_tm):
    # Search if data already exists or not.
    subdir_list = os.listdir("/tmp/")
    for subdir in subdir_list:
        if re.match("compliance-[0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}", subdir):


            metadata_filename = "/tmp/"+subdir+"/__compliance_metadata.txt"
            if os.path.exists(metadata_filename):
                f = open(metadata_filename,'r')
                fcontent = f.readlines()
                f.close()
                f_nm = fcontent[0].strip()
                f_tm = fcontent[1].strip()
                #print in_namespace, in_tm[0:19], f_nm, f_tm[0:19]
                if f_nm==in_namespace and f_tm[0:19]==in_tm[0:19]:
                    #print "* Uncrawl directory found for", in_namespace, in_tm
                    print "    Uncrawl directory path:", subdir
                    return "/tmp/"+subdir
    return ""

def CheckCompliance(prefix, comp_id, nmspace, crawltm, req_id, estatus):
    output = "{\n"
    output = output + "\"compliance_id\":\""+comp_id+"\",\n"
    output = output + "\"description\":\""+DescriptionDict[comp_id]+"\",\n"
    current_command = "./comp."+comp_id+".sh "+prefix

    # If status is not 0, there was something wrong in previous step. So, don't execute script.
    if estatus==0:
        p = subprocess.Popen(current_command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        for line in p.stdout.readlines():
            output = output + line.strip()+"\n"
    else:
        output = output + "\"compliant\":\"unknown\",\n"
        output = output + "\"reason\":\"not applicable\",\n"

    output = output + "\"execution_status\":\""+StatusDict[estatus]+"\",\n"
    output = output + "\"namespace\":\""+nmspace+"\",\n"
    output = output + "\"crawled_time\":\""+crawltm+"\",\n"
    output = output + "\"compliance_check_time\":\""+datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")+"\",\n"
    output = output + "\"request_id\":\""+req_id+"\"\n"
    output = output + "}\n"

    return output

def EmitResultToCloudSight(datastr):
    try:
        url = "kafka://"+kafka_ip_port+"/compliance"
        list = url[len('kafka://'):].split('/')
        if len(list) == 2:
            kurl = list[0]
            topic = list[1]
        else:
            raise Exception("Invalid kafka url:" % (url))

        kafka = KafkaClient(kurl)
        producer = SimpleProducer(kafka)
        producer.client.ensure_topic_exists(topic)
        producer.send_messages(topic, datastr)
        producer.stop()
    except Exception, e:
        raise

def RemoveTempContent(dirname):
    cmd = "rm -rf "+dirname
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
