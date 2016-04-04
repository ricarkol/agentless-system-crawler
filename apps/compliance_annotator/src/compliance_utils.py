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
import logging
import logging.handlers

###############################################################
# CONFIGURATION
###############################################################


# demo3 environment
#myserver_domain_name="r2d2.sl.cloud9.ibm.com"
#kafka_group_id="compliance-annotator-r2d2"
#search_service_ip_port="demo3.sl.cloud9.ibm.com:8885"
#kafka_ip_port="demo3.sl.cloud9.ibm.com:9092"
#elasticsearch_ip_port="demo3.sl.cloud9.ibm.com:9200"
#temporary_directory="/tmp"
#annotator_home="/var/www/html/kafka-compliance-demo3"

# cloudsight environment
myserver_domain_name="r2d2.sl.cloud9.ibm.com"
kafka_group_id="compliance-annotator"
search_service_ip_port="cloudsight.sl.cloud9.ibm.com:8885"
kafka_ip_port="kafka-cs.sl.cloud9.ibm.com:9092"
elasticsearch_ip_port="elastic2-cs.sl.cloud9.ibm.com:9200"
temporary_directory="/tmp"
annotator_home="/var/www/html/kafka-compliance-cloudsight"

# watson environment
#search_service_ip_port="10.26.77.191:8885"
#kafka_ip_port="10.109.223.165:9092"

crawl_annotation_report_delay=5 # for report.html generation only, without using search service


###############################################################


compliance_rule_list = [
    "Linux.1-1-a",
    "Linux.2-1-b",
    "Linux.2-1-c",
    "Linux.2-1-d",
#    "Linux.2-1-e",
#    "Linux.2-1-f",
#    "Linux.3-1-a",
#    "Linux.3-2-b",
#    "Linux.3-2-e",
#    "Linux.3-2-f",
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
    "Linux.9-0-a",
    "Linux.9-0-b",
    "Linux.9-0-c",
    "Linux.9-0-d",
    "Linux.20-0-a",
]


StatusDict = {
    0: "Success",
    1: "Feature data not available.",
    2: "Search service not reachable.",
    3: "Required file or directory missing.",
    4: "Uncrawled data unavailable."
}

DescriptionDict = {
    "Linux.1-1-a": "Each UID must be used only once.",
    "Linux.2-1-b": "Maximum password age must be set to 90 days.",
    "Linux.2-1-c": "Minimum password length must be 8.",
    "Linux.2-1-d": "Minimum days that must elapse between user-initiated password changes should be 1.",
    "Linux.2-1-e": "Reuse of password must be restricted to eight.",
    "Linux.3-1-a": "motd file checking",
    "Linux.3-2-b": "UMASK value 077 in /etc/login.defs",
    "Linux.3-2-e": "/etc/profile",
    "Linux.3-2-f": "/etc/csh.login",
    "Linux.5-1-a": "Read/write access of ~root/.rhosts only by root",
    "Linux.5-1-b": "Read/write access of ~root/.netrc only by root",
    "Linux.5-1-d": "Permission of /usr must be r-x or more restrictive.",
    "Linux.5-1-e": "Permission of /etc must be r-x or more restrictive.",
    "Linux.5-1-f": "The file /etc/security/opasswd must exist and the permission must be rw------- or more restrictive.",
    "Linux.5-1-g": "Permission of /etc/shadow must be rw------- or more restrictive.",
    "Linux.5-1-h": "File /etc/profile.d/IBMsinit.sh must have r-x for other and r-x for group.",
    "Linux.5-1-i": "File /etc/profile.d/IBMsinit.csh must have r-x for other and r-x for group.",
    "Linux.5-1-j": "Permission settings of /var for other must be r-x or more restrictive.",
    "Linux.5-1-k": "Permission of /var/tmp must be rwxrwxrwt.",
    "Linux.5-1-l": "Permission setting of /var/log for other must be r-x or more restrictive.",
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
    "Linux.9-0-a": "checking if ssh server is installed",
    "Linux.9-0-b": "checking if telnet server is installed",
    "Linux.9-0-c": "checking if rsh server is installed",
    "Linux.9-0-d": "checking if ftp server is installed",
    "Linux.20-0-a": "checking if ssh server is disabled",
}

#btime="2015-04-23T01:01:01Z"
#etime="2015-04-25T05:50:01Z"
btime=(datetime.datetime.utcnow()-datetime.timedelta(minutes=10)).strftime("%Y-%m-%dT%H:%M:%SZ")
etime=(datetime.datetime.utcnow()+datetime.timedelta(minutes=1)).strftime("%Y-%m-%dT%H:%M:%SZ")

def GetUncrawlDirectoryName(in_namespace, in_tm):
    # Search if data already exists or not.
    subdir_list = os.listdir(temporary_directory+"/")
    for subdir in subdir_list:
        if re.match("compliance-[0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}", subdir):

            metadata_filename = temporary_directory+"/"+subdir+"/__compliance_metadata.txt"
            if os.path.exists(metadata_filename):
                #f = open(metadata_filename,'r')
                #fcontent = f.readlines()
                #f.close()
                #f_nm = fcontent[0].strip()
                #f_tm = fcontent[1].strip()
                #f_onm = fcontent[2].strip() # owner_namespace == tenant

                metadata_dict = json.load(open(metadata_filename))
                f_nm = metadata_dict['namespace']  # namespace
                f_tm = metadata_dict['timestamp']  # timestamp
                f_onm = metadata_dict['owner_namespace'] # owner_namespace == tenant

                # WARNING: if you enable print below, it will cause the indexing to fail.
                #print "GetUncrawlDirectoryName()", in_namespace, in_tm, f_nm, f_tm
                if f_nm==in_namespace and f_tm==in_tm:
                    #print "* Uncrawl directory found for", in_namespace, in_tm
                    #print "    Uncrawl directory path:", subdir
                    return temporary_directory+"/"+subdir
    return ""

def DoComplianceChecking(prefix, comp_id, nmspace, crawltm, req_id, logger):

    #logger.info(comp_id)
    outstr=""
    ret_status = 0

    packages_filename = prefix+"/__compliance_packages.txt"
    if comp_id=="Linux.9-0-a":

        if os.path.exists(packages_filename):
            with open(packages_filename) as f:
                content = f.readlines()
        else:
            logger.info("ERROR package file not found while checking 9-0-a.",nmspace,crawltm)
            content = []
    
        # Initialize
        str_compliant = "true"
        str_reason = "SSH server not found"
    
        for pkgline in content:
            pkgname = pkgline.strip().split()[0]
            if pkgname=="openssh-server":
                version_info = ""
                if len(pkgline.strip().split())==2:
                    version_info = " of version "+pkgline.strip().split()[1]
                str_compliant = "false"
                str_reason = "SSH server package, "+pkgname+version_info+", found. "
                break;
    
        for pkgline in content:
            pkgname = pkgline.strip().split()[0]
            if pkgname=="openssh-sftp-server":
                version_info = ""
                if len(pkgline.strip().split())==2:
                    version_info = " of version "+pkgline.strip().split()[1]
                str_compliant = "false"
                str_reason = str_reason + "SSH server package, "+pkgname+version_info+", found. " # str_reason is appended to the previous one
                break;

        outstr = "{"
        outstr = outstr + "\"compliance_id\":\""+comp_id+"\","
        outstr = outstr + "\"description\":\""+DescriptionDict[comp_id]+"\","
        outstr = outstr + "\"compliant\":\""+str_compliant+"\","
        outstr = outstr + "\"reason\":\""+str_reason+"\","
        outstr = outstr + "\"execution_status\":\""+StatusDict[ret_status]+"\","
        outstr = outstr + "\"namespace\":\""+nmspace+"\","
        outstr = outstr + "\"crawled_time\":\""+crawltm+"\","
        outstr = outstr + "\"compliance_check_time\":\""+datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")+"\","
        outstr = outstr + "\"request_id\":\""+str(req_id)+"\""
        outstr = outstr + "}\n"

    elif comp_id=="Linux.9-0-b":

        if os.path.exists(packages_filename):
            with open(packages_filename) as f:
                content = f.readlines()
        else:
            logger.info("ERROR package file not found while checking 9-0-b.",nmspace,crawltm)
            content = []
    
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
    
        outstr = "{"
        outstr = outstr + "\"compliance_id\":\""+comp_id+"\","
        outstr = outstr + "\"description\":\""+DescriptionDict[comp_id]+"\","
        outstr = outstr + "\"compliant\":\""+str_compliant+"\","
        outstr = outstr + "\"reason\":\""+str_reason+"\","
        outstr = outstr + "\"execution_status\":\""+StatusDict[ret_status]+"\","
        outstr = outstr + "\"namespace\":\""+nmspace+"\","
        outstr = outstr + "\"crawled_time\":\""+crawltm+"\","
        outstr = outstr + "\"compliance_check_time\":\""+datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")+"\","
        outstr = outstr + "\"request_id\":\""+str(req_id)+"\""
        outstr = outstr + "}\n"
    
    elif comp_id=="Linux.9-0-c":

        if os.path.exists(packages_filename):
            with open(packages_filename) as f:
                content = f.readlines()
        else:
            logger.info("ERROR package file not found while checking 9-0-c.",nmspace,crawltm)
            content = []
    
        # Initialize
        str_compliant = "true"
        str_reason = "rsh server not found"
    
        for pkgline in content:
            pkgname = pkgline.strip().split()[0]
            if pkgname=="rssh":
                version_info = ""
                if len(pkgline.strip().split())==2:
                    version_info = " of version "+pkgline.strip().split()[1]
                str_compliant = "false"
                str_reason = "rsh server package, "+pkgname+version_info+", found. "
                break;
    
        outstr = "{"
        outstr = outstr + "\"compliance_id\":\""+comp_id+"\","
        outstr = outstr + "\"description\":\""+DescriptionDict[comp_id]+"\","
        outstr = outstr + "\"compliant\":\""+str_compliant+"\","
        outstr = outstr + "\"reason\":\""+str_reason+"\","
        outstr = outstr + "\"execution_status\":\""+StatusDict[ret_status]+"\","
        outstr = outstr + "\"namespace\":\""+nmspace+"\","
        outstr = outstr + "\"crawled_time\":\""+crawltm+"\","
        outstr = outstr + "\"compliance_check_time\":\""+datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")+"\","
        outstr = outstr + "\"request_id\":\""+str(req_id)+"\""
        outstr = outstr + "}\n"

    elif comp_id=="Linux.9-0-d":

        if os.path.exists(packages_filename):
            with open(packages_filename) as f:
                content = f.readlines()
        else:
            logger.info("ERROR package file not found while checking 9-0-d.",nmspace,crawltm)
            content = []

        # Initialize
        str_compliant = "true"
        str_reason = "ftp server not found"
    
        for pkgline in content:
            pkgname = pkgline.strip().split()[0]
            if pkgname=="ftpd":
                version_info = ""
                if len(pkgline.strip().split())==2:
                    version_info = " of version "+pkgline.strip().split()[1]
                str_compliant = "false"
                str_reason = "ftp server package, "+pkgname+version_info+", found. "
                break;
    
        for pkgline in content:
            pkgname = pkgline.strip().split()[0]
            if pkgname=="ftpd-ssl":
                version_info = ""
                if len(pkgline.strip().split())==2:
                    version_info = " of version "+pkgline.strip().split()[1]
                str_compliant = "false"
                str_reason = str_reason + "ftp server package, "+pkgname+version_info+", found. " # str_reason is appended to the previous one
                break;
    
        for pkgline in content:
            pkgname = pkgline.strip().split()[0]
            if pkgname=="tftpd-hpa":
                version_info = ""
                if len(pkgline.strip().split())==2:
                    version_info = " of version "+pkgline.strip().split()[1]
                str_compliant = "false"
                str_reason = str_reason + "ftp server package, "+pkgname+version_info+", found. " # str_reason is appended to the previous one
                break;
    
        for pkgline in content:
            pkgname = pkgline.strip().split()[0]
            if pkgname=="vsftpd":
                version_info = ""
                if len(pkgline.strip().split())==2:
                    version_info = " of version "+pkgline.strip().split()[1]
                str_compliant = "false"
                str_reason = str_reason + "ftp server package, "+pkgname+version_info+", found. " # str_reason is appended to the previous one
                break;
    
        for pkgline in content:
            pkgname = pkgline.strip().split()[0]
            if pkgname=="atftpd":
                version_info = ""
                if len(pkgline.strip().split())==2:
                    version_info = " of version "+pkgline.strip().split()[1]
                str_compliant = "false"
                str_reason = str_reason + "ftp server package, "+pkgname+version_info+", found. " # str_reason is appended to the previous one
                break;
    
        for pkgline in content:
            pkgname = pkgline.strip().split()[0]
            if pkgname=="pure-ftpd":
                version_info = ""
                if len(pkgline.strip().split())==2:
                    version_info = " of version "+pkgline.strip().split()[1]
                str_compliant = "false"
                str_reason = str_reason + "ftp server package, "+pkgname+version_info+", found. " # str_reason is appended to the previous one
                break;
    
        outstr = "{"
        outstr = outstr + "\"compliance_id\":\""+comp_id+"\","
        outstr = outstr + "\"description\":\""+DescriptionDict[comp_id]+"\","
        outstr = outstr + "\"compliant\":\""+str_compliant+"\","
        outstr = outstr + "\"reason\":\""+str_reason+"\","
        outstr = outstr + "\"execution_status\":\""+StatusDict[ret_status]+"\","
        outstr = outstr + "\"namespace\":\""+nmspace+"\","
        outstr = outstr + "\"crawled_time\":\""+crawltm+"\","
        outstr = outstr + "\"compliance_check_time\":\""+datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")+"\","
        outstr = outstr + "\"request_id\":\""+str(req_id)+"\""
        outstr = outstr + "}\n"

    elif comp_id=="Linux.20-0-a":

        target_filename = prefix+"/etc/init/ssh.conf"
        if os.path.exists(target_filename):
            str_compliant = "false"
            str_reason = "SSH server is enabled"
        else:
            str_compliant = "true"
            str_reason = "SSH server is disabled"

        outstr = "{"
        outstr = outstr + "\"compliance_id\":\""+comp_id+"\","
        outstr = outstr + "\"description\":\""+DescriptionDict[comp_id]+"\","
        outstr = outstr + "\"compliant\":\""+str_compliant+"\","
        outstr = outstr + "\"reason\":\""+str_reason+"\","
        outstr = outstr + "\"execution_status\":\""+StatusDict[ret_status]+"\","
        outstr = outstr + "\"namespace\":\""+nmspace+"\","
        outstr = outstr + "\"crawled_time\":\""+crawltm+"\","
        outstr = outstr + "\"compliance_check_time\":\""+datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")+"\","
        outstr = outstr + "\"request_id\":\""+str(req_id)+"\""
        outstr = outstr + "}\n"

    else:
        outstr = "{"
        outstr = outstr + "\"compliance_id\":\""+comp_id+"\","
        outstr = outstr + "\"description\":\""+DescriptionDict[comp_id]+"\","
        current_command = "./comp."+comp_id+".sh "+prefix

        p = subprocess.Popen(current_command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        for line in p.stdout.readlines():
            outstr = outstr + line.strip()

        outstr = outstr + "\"execution_status\":\""+StatusDict[ret_status]+"\","
        outstr = outstr + "\"namespace\":\""+nmspace+"\","
        outstr = outstr + "\"crawled_time\":\""+crawltm+"\","
        outstr = outstr + "\"compliance_check_time\":\""+datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")+"\","
        outstr = outstr + "\"request_id\":\""+str(req_id)+"\""
        outstr = outstr + "}\n"

    return outstr


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
    output = output + "\"request_id\":\""+str(req_id)+"\"\n"
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
