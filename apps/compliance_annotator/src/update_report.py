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
import argparse
import ConfigParser
import stat
from collections import defaultdict
from kafka import KafkaClient, SimpleProducer, KeyedProducer
from urllib2 import Request, urlopen, URLError
import difflib
from compliance_utils import *

# How many entries to show on the dashboard page, how many .html report files to maintain in compliance_reports and vulnerability_reports dir
DASHBOARD_LENGTH=1000

if __name__ == '__main__':

    try:
        parser = argparse.ArgumentParser(description="")
        parser.add_argument('--kafka-url',  type=str, required=True, help='kafka url: host:port')
        parser.add_argument('--receive-topic', type=str, required=True, help='receive-topic')
        parser.add_argument('--notification-topic', type=str, required=True, help='topic to send process notification')
        parser.add_argument('--annotation-topic', type=str, required=True, help='topic to send annotations')
        parser.add_argument('--elasticsearch-url',  type=str, required=True, help='elasticsearch url: host:port')
        parser.add_argument('--annotator-home', type=str, required=True, help='full path of annotator')
        parser.add_argument('--instance-id',  type=str, required=True, help='instance id')

        args = parser.parse_args()
        elasticsearch_ip_port = args.elasticsearch_url
        kafka_ip_port = args.kafka_url
        annotator_home = args.annotator_home
    except Exception, e:
        print('Error: %s' % str(e))

    os.chdir(annotator_home)

    ##################################################################################################
    # I dynamically generate this file (HTML table header) instead of putting it to the report_header.html because columns may change.
    fp = open("report_body_table_header.html","w")
    #fp.write("<tr>")
    #fp.write("<th align=center rowspan=2><b>Owner Namespace</b></th>")
    #fp.write("<th align=center rowspan=2><b>Namespace</b></th>")
    #fp.write("<th align=center rowspan=2><b>Registry</b></th>")
    #fp.write("<th align=center rowspan=2><b>Image Name</b></th>")
    #fp.write("<th align=center rowspan=2><b>Tag</b></th>")
    #fp.write("<th align=center rowspan=2><b>Crawl Time (UTC)</b></th>")
    #fp.write("<th align=center rowspan=2><b>Vulnerability</b></th>")
    #fp.write("<th align=center rowspan=2><b>Noncompliance</b></th>")
    #fp.write("<th align=center colspan="+str(len(compliance_rule_list))+"><b>ITCS104 Compliance</b>&nbsp;<font size=1><a href=\"http://w3-03.ibm.com/transform/sas/as-web.nsf/ContentDocsByTitle/Linux+Appendix\" target=\"_blank\">(link)</a></font></th>")
    #fp.write("</tr>\n")
    #fp.write("<tr>")
    #for k in compliance_rule_list:
    #    fp.write("<th align=center title=\""+DescriptionDict[k]+"\" width=34px><b>"+k.replace("Linux.","")+"</b></th>")
    #fp.write("</tr>\n")
 
    fp.write("<tr>")
    fp.write("<th align=center rowspan=1><b>Owner Namespace</b></th>")
    fp.write("<th align=center rowspan=1><b>Namespace</b></th>")
    fp.write("<th align=center rowspan=1><b>Registry</b></th>")
    fp.write("<th align=center rowspan=1><b>Image Name</b></th>")
    fp.write("<th align=center rowspan=1><b>Tag</b></th>")
    fp.write("<th align=center rowspan=1><b>Crawl Time (UTC)</b></th>")
    fp.write("<th align=center rowspan=1><b>Vulnerability</b></th>")
    fp.write("<th align=center rowspan=1><b>Noncompliance</b></th>")
    fp.write("</tr>\n")
    fp.close()


    ######################################################################
    # Get the list of newly created uncrawl directories and extract nm and tm
    # Make dictionary of time:namespace for all the new namespaces so that I can sort new namespaces by timestamp
    tm_nm_dict=defaultdict(list)
    tm_onm_dict=defaultdict(list)
    tm_registry_dict=defaultdict(list)
    tm_imgname_dict=defaultdict(list)
    tm_imgtag_dict=defaultdict(list)
    subdir_list = os.listdir(temporary_directory+"/")
    for subdir in subdir_list:
        if re.match("compliance-[0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}", subdir):

            metadata_filename = temporary_directory+"/"+subdir+"/__compliance_metadata.txt"
            if os.path.exists(metadata_filename):
                #f = open(metadata_filename,'r')
                #fcontent = f.readlines()
                #f.close()
                #f_nm = fcontent[0].strip()  # namespace
                #f_tm = fcontent[1].strip()  # timestamp
                #f_onm = fcontent[2].strip() # owner_namespace == tenant

                metadata_dict = json.load(open(metadata_filename))
                f_nm = metadata_dict['namespace']  # namespace
                f_tm = metadata_dict['timestamp']  # timestamp
                f_onm = metadata_dict['owner_namespace'] # owner_namespace == tenant
                f_registry = metadata_dict['docker_image_registry']
                f_imgname = metadata_dict['docker_image_short_name']
                f_imgtag = metadata_dict['docker_image_tag']

                tm_nm_dict[f_tm].append(f_nm) 
                tm_onm_dict[f_tm].append(f_onm) 
                tm_registry_dict[f_tm].append(f_registry)
                tm_imgname_dict[f_tm].append(f_imgname)
                tm_imgtag_dict[f_tm].append(f_imgtag)
                print "Appending",f_tm,f_nm,f_onm

    # For one timestamp, there can be multiple namespaces.
    request_id = 0
    status_new_namespace=""
    for tmstr in sorted(tm_nm_dict.keys(),reverse=True):
        for i in range(0,len(tm_nm_dict[tmstr])):
            nm = tm_nm_dict[tmstr][i]
            onm = tm_onm_dict[tmstr][i]
            rgt = tm_registry_dict[tmstr][i]
            imgnm = tm_imgname_dict[tmstr][i]
            imgtag = tm_imgtag_dict[tmstr][i]
            
            tm = tmstr
            print "[",nm,tm,"]"

            ## Skip if already uncrawled
            mydir = GetUncrawlDirectoryName(nm, tm)
            if mydir=="":
                print "[",nm,tm,"]","Crawl directory not found. Perhaps already processed."
                continue

#            # Skip if crawl time is less than crawl_annotation_report_delay seconds ago
#            now = datetime.datetime.utcnow()
#            #crawltm_adjusted= re.sub("\.[0-9][0-9][0-9]Z", "Z", tm)
#            crawltm_adjusted= tm.strip()[0:19]+"Z"
#            crwl = time.strptime(crawltm_adjusted, "%Y-%m-%dT%H:%M:%SZ")
#            crawltm = datetime.datetime(crwl.tm_year, crwl.tm_mon, crwl.tm_mday, crwl.tm_hour, crwl.tm_min, crwl.tm_sec)
#            sec_diff = (now-crawltm).total_seconds()
#            if sec_diff<crawl_annotation_report_delay:
#                print "INFO: Too early to fetch data. It is crawled only "+str(sec_diff)+" seconds ago. Skipping ..."
#                if status_new_namespace=="":
#                    #status_new_namespace=nm.split("/")[0]
#                    status_new_namespace=nm
#                else:
#                    #status_new_namespace=status_new_namespace+", "+nm.split("/")[0]
#                    status_new_namespace=status_new_namespace+", "+nm
#                continue
#            print "INFO: Time since crawling is "+str(sec_diff)+" seconds."

            # Check if compliance results are available in ES yet.
            cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-*/_search?pretty -d '{ \"query\": { \"bool\":{ \"must\": [ { \"match_phrase_prefix\": { \"namespace.raw\" : \""+nm+"\" } }, { \"match\": { \"crawled_time\":\""+tm+"\" } } ]}}, \"size\":\"100\" }'"
            print "<1>",cmd
            p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            ret = ""
            for line in p.stdout.readlines():
                ret = ret+line
            if ret=="":
                print "[",nm,tm,"]","No compliance results are available. Skipping ..."
                continue
            cmp_data = []
            if ret != "":
                cmp_data = json.loads(ret)["hits"]["hits"]

            # Check if all the compliance resutls are indexed into ES
            rule_count = 0
            for rule_id in compliance_rule_list:
                for comp_result in range(0, len(cmp_data)):
                    json_str = json.dumps(cmp_data[comp_result])
                    json_data = json.loads(json_str)
                    field_compliance_id = json_data["_source"]["compliance_id"]
                    if rule_id.strip()==field_compliance_id.strip():
                        rule_count = rule_count + 1

            # Print if overall compliance T/F record exists or not.
            for comp_result in range(0, len(cmp_data)):
                json_str = json.dumps(cmp_data[comp_result])
                json_data = json.loads(json_str)
                field_compliance_id = json_data["_source"]["compliance_id"]
                if field_compliance_id.strip()=="Linux.0-0-a":
                    print "[",nm,tm,"]","Overall Compliance T/F record found!"

            if rule_count < len(compliance_rule_list):
                print "[",nm,tm,"]","Waiting for all compliance results to be indexed. Current count is "+str(len(cmp_data))+"."
                continue

            # Run compliance checking
            with open("report_body.html","a") as report_body:
                report_body.write ("<tr>")

                report_body.write("<td align=center>"+onm+"</td>")
                report_body.write("<td align=center>"+nm+"</td>")
                report_body.write("<td align=center>"+rgt+"</td>")
                report_body.write("<td align=center>"+imgnm+"</td>")
                report_body.write("<td align=center>"+imgtag+"</td>")
                #report_body.write("<td align=center>"+tm.split(".")[0].replace("Z"," ").replace("T"," ")+"</td>")
                report_body.write("<td align=center>"+tm+"</td>")

                # Add column for vulnerability
                cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/vulnerabilityscan-*/vulnerabilityscan/_search?pretty -d '{ \"query\": { \"filtered\": { \"filter\": { \"exists\": { \"field\":\"package_name\" } }, \"query\":{ \"bool\":{ \"must\":[{ \"match_phrase_prefix\":{ \"namespace.raw\":\""+nm+"\" } }, { \"match\":{ \"timestamp\":\""+tm+"\" } }] } } } }, \"size\":1000 }'"
                print "<2>",cmd
                p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                ret = ""
                for line in p.stdout.readlines():
                    ret = ret+line
                vl_data = []
                if ret != "":
                    vl_data = json.loads(ret)["hits"]["hits"]

                # Generate vulnerability report
                vulnerability_reports_dir_name="vulnerability_reports"
                if not os.path.exists(vulnerability_reports_dir_name):
                    os.makedirs(vulnerability_reports_dir_name)
                    os.chmod(vulnerability_reports_dir_name,0o755)
                vfilename=vulnerability_reports_dir_name+"/"+"vulnerability-report-"+str(uuid.uuid4()).replace("-","")+".html"

                fp=open(vfilename,"w")
                fp.write("<html> <head> <style type='text/css'> .myTable { background-color:#FFFFFF;border-collapse:collapse; } .myTable th { background-color:#6B7De7;color:white; font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 13px; } .myTable td, .myTable th { padding:5px;border:1px solid #111111; font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 12px; } </style> </head> <body>")
                fp.write("<a href=\"javascript:history.back()\"><b>[Return to Main]</b></a>\n")
                fp.write("<br/>\n")
                fp.write("<h3>Vulnerability Report</h3>\n")
                fp.write("Registry URL: "+nm.split("/")[0]+"\n")
                fp.write("<br/>\n")
                if len(nm.split("/"))>1:
                    fp.write("Namespace: "+nm.split("/")[1]+"\n")
                    fp.write("<br/>\n")
                fp.write("Timestamp: "+tm+"\n")
                fp.write("<br/>\n")
                fp.write("<br/>\n")
                fp.write("<table class=myTable>\n")
                fp.write("<tr><th>Package Name</th><th>Current Version</th><th>Fix Version</th><th>Vulnerable</th><th>Distro</th></tr>\n")

                for vul in range(0,len(vl_data)):
                    json_str = json.dumps(vl_data[vul])
                    json_data = json.loads(json_str)

                    v_package_name     =json_data["_source"]["package_name"]
                    v_current_version =json_data["_source"]["current_version"]
                    v_fix_version =json_data["_source"]["fix_version"]
                    v_vulnerable=str(json_data["_source"]["vulnerable"]).strip()
                    v_distro   =json_data["_source"]["distro"]
                    fp.write("<tr>")
                    fp.write("<td>"+str(v_package_name)+"</td>")
                    fp.write("<td>"+str(v_current_version)+"</td>")
                    fp.write("<td>"+str(v_fix_version)+"</td>")
                    if v_vulnerable=="true":
                        fp.write("<td align=center style=\"background-color:#ffcccc\"><b><font color=#ff3333>"+str(v_vulnerable)+"</font></b></td>")
                    else:
                        fp.write("<td align=center>"+str(v_vulnerable)+"</td>")
                    fp.write("<td>"+str(v_distro)+"</td>")
                    fp.write("</tr>\n")
                fp.write("</table>")
                fp.write("<br/>")
                fp.write("<a href=\"javascript:history.back()\"><b>[Return to Main]</b></a>\n")
                fp.write("</body></html>")
                fp.close()

                # Obtain overall vulnerability verdict counts
                # TODO: v_count and v_total obtained from above is not used. I directly pull those numbers from the verdict API. Need to clean up the code above.
                cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/vulnerabilityscan-*/vulnerabilityscan/_search?pretty -d ' {\"query\": { \"bool\":{ \"must\": [ { \"match_phrase_prefix\": { \"namespace.raw\" : \""+nm+"\" } }, { \"match_phrase_prefix\": { \"description\" : \"Overall vulnerability status\" } } ]} }, \"size\":\"1\", \"sort\": { \"@timestamp\": { \"order\": \"desc\", \"ignore_unmapped\": true } } }' "
                print "<3>",cmd
                p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                ret = ""
                for line in p.stdout.readlines():
                    ret = ret+line
                vulcount_data = []
                if ret != "":
                    vulcount_data = json.loads(ret)["hits"]["hits"]

                if len(vulcount_data)>0:
                    json_str = json.dumps(vulcount_data[0])
                    json_data = json.loads(json_str)
                    vul_count = json_data["_source"]["vulnerable_packages"]
                    vul_total = json_data["_source"]["total_packages"]
                else:

                    print "[",nm,tm,"]","WARNING: No vulnerability data found."
                    vul_count = 0
                    vul_total = 0
                    
                if vul_count>0:
                    report_body.write("<td align=center style=\"background-color:#ffcccc\"><a href=\""+vfilename+"\"><b><font color=#ff3333>"+str(vul_count)+"/"+str(vul_total)+"</font></b></a></td>\n")
                else:
                    report_body.write("<td align=center><a href=\""+vfilename+"\">"+str(vul_count)+"/"+str(vul_total)+"</a></td>\n")


            # Run compliance rules. Compliance rule writes the result to report_body.html thru CheckCompliance function.
            #for cname in compliance_rule_list:
            #    result_obtained=False
            #    # for a given compliance ID, I loop through the results to find the one I want.
            #    # resutl_obtained is used to skip the loops once I found the result for the compliance ID I wanted.
            #    for comp_result in range(0,len(cmp_data)):
            #        json_str = json.dumps(cmp_data[comp_result])
            #        json_data = json.loads(json_str)
            #
            #        if not result_obtained and cname==json_data["_source"]["compliance_id"]:
            #            
            #            field_compliant=json_data["_source"]["compliant"]
            #            with open("report_body.html","a") as myfile:
            #                if field_compliant=="true":
            #                    myfile.write ("<td align=center>Pass</td>")
            #                elif field_compliant=="false":
            #                    myfile.write ("<td align=center style=\"background-color:#ffcccc\"><b><font color=\"#ff3333\">Fail</b></td>")
            #                else:
            #                    myfile.write ("<td align=center >Wait</td>")
            #                print cname, json_data["_source"]["compliance_id"], json_data["_source"]["compliant"], field_compliant
            #                result_obtained=True

            # Generate compliance report
            compliance_reports_dir_name="compliance_reports"
            if not os.path.exists(compliance_reports_dir_name):
                os.makedirs(compliance_reports_dir_name)
                os.chmod(compliance_reports_dir_name,0o755)
            cfilename=compliance_reports_dir_name+"/"+"compliance-report-"+str(uuid.uuid4()).replace("-","")+".html"

            fp=open(cfilename,"w")
            fp.write("<html> <head> <style type='text/css'> .myTable { background-color:#FFFFFF;border-collapse:collapse; } .myTable th { background-color:#6B7De7;color:white; font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 13px; } .myTable td, .myTable th { padding:5px;border:1px solid #111111; font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 12px; } </style> </head> <body>")
            fp.write("<a href=\"javascript:history.back()\"><b>[Return to Main]</b></a>\n")
            fp.write("<br/>\n")
            fp.write("<h3>Noncompliance Report</h3>\n")
            fp.write("Registry URL: "+nm.split("/")[0]+"\n")
            fp.write("<br/>\n")
            if len(nm.split("/"))>1:
                fp.write("Namespace: "+nm.split("/")[1]+"\n")
                fp.write("<br/>\n")
            fp.write("Timestamp: "+tm+"\n")
            fp.write("<br/>\n")
            fp.write("<br/>\n")
            fp.write("<table class=myTable>\n")
            fp.write("<tr><th>Compliance ID</th><th>Compliance Description</th><th>Compliance</th><th>Reason</th></tr>\n")
            for cname in compliance_rule_list:
                fp.write("<tr>")
                result_obtained=False
                for comp_result in range(0,len(cmp_data)):
                    json_str = json.dumps(cmp_data[comp_result])
                    json_data = json.loads(json_str)
                    if not result_obtained and cname==json_data["_source"]["compliance_id"]:
                        # Compliance ID column
                        fp.write("<td>"+cname+"</td>\n")
                        # Compliance Description column
                        fp.write("<td>"+DescriptionDict[cname]+"</td>\n")
                        # Compliance result column
                        field_compliant=json_data["_source"]["compliant"]
                        if field_compliant=="true":
                            fp.write ("<td align=center>Pass</td>")
                        elif field_compliant=="false":
                            fp.write ("<td align=center style=\"background-color:#ffcccc\"><b><font color=\"#ff3333\">Fail</b></td>")
                        else:
                            fp.write ("<td align=center >Wait</td>")
                        print cname, json_data["_source"]["compliance_id"], json_data["_source"]["compliant"], field_compliant
                        # Compliance reason column
                        fp.write("<td>"+json_data["_source"]["reason"]+"</td>\n")
                        result_obtained=True
                fp.write("</tr>\n")
            fp.write("</table>")
            fp.write("<br/>")
            fp.write("<a href=\"javascript:history.back()\"><b>[Return to Main]</b></a>\n")
            fp.write("</body></html>")
            fp.close()

            compliant_count=0
            for comp_result in range(0, len(cmp_data)):
                json_str = json.dumps(cmp_data[comp_result])
                json_data = json.loads(json_str)
                field_compliant=json_data["_source"]["compliant"]
                field_timestamp=json_data["_source"]["crawled_time"]
                if json_data["_source"]["compliance_id"]=="Linux.0-0-a":
                    continue
                if field_compliant=="false" and field_timestamp==tm:
                    compliant_count=compliant_count+1
            # Make column for overall compliant verdict
            with open("report_body.html","a") as report_body:
                if compliant_count>0:
                    report_body.write("<td align=center style=\"background-color:#ffcccc\"><a href=\""+cfilename+"\"><b><font color=#ff3333>"+str(compliant_count)+"/"+str(len(compliance_rule_list))+"</font></b></a></td>\n")
                else:
                    report_body.write("<td align=center><a href=\""+cfilename+"\">"+str(compliant_count)+"/"+str(len(compliance_rule_list))+"</a></td>\n")

            with open("report_body.html","a") as report_body:
                report_body.write ("</tr>\n")

            # Delete uncrawled data
            prefix = GetUncrawlDirectoryName(nm, tm)
            if prefix=="":
                print "[",nm,tm,"]","WARNING: Uncrawl directory not found!"
            else:
                RemoveTempContent(prefix)

    # Compose the compliance report
    with open("report_header.html","r") as fp:
        header_data = fp.read()

    with open("report_body_table_header.html","r") as fp:
        body_table_header_data = fp.read()

    body_data=""
    if os.path.isfile("report_body.html"):
        with open("report_body.html","r") as fp:
            body_data = fp.read()

    # 2015 Jun 29, For body_data_past, I am pruning it to have only the top 1000 <tr></tr> lines.
    # To do that, I read the file, split line by line and concatenate only the first 1000 lines.
    body_data_past=""
    tmp_html_data=""
    if os.path.isfile("report_body_past.html"):
        with open("report_body_past.html","r") as fp:
            tmp_html_data = fp.read()

    split_html_data = re.split('\n',tmp_html_data)

    for n in range(0,len(split_html_data)):
        if n<DASHBOARD_LENGTH:
            body_data_past=body_data_past+split_html_data[n]

    with open("report_footer.html","r") as fp:
        footer_data = fp.read()
    with open("report.html","w") as fp:
        if status_new_namespace=="":
            status_new_namespace="None"
        status_message="Compliance checking in progress for these images: <font color=blue><b>"+status_new_namespace+"</b></font><br/>"
        status_message=""
        fp.write(header_data+"\n"+status_message+"\n<table class=myTable>\n"+body_table_header_data+"\n"+body_data+"\n"+body_data_past+"\n"+footer_data)

    # Delete existing report_body_past.html and regenerate new one with the most recent entry at the top
    if os.path.isfile("report_body_past.html"):
        os.unlink("report_body_past.html")
    with open("report_body_past.html","w") as fp:
        if not body_data=="":
            fp.write(body_data+"\n"+body_data_past)
        else:
            fp.write(body_data_past)

    # Get rid of report_body.html now.
    if os.path.isfile("report_body.html"):
        os.unlink("report_body.html")

    # 2015 Jun 25: Remove old compliance reports and vulnerability reports
    target_dir="compliance_reports"
    files = []
    if os.path.exists(target_dir):
        files = os.listdir(target_dir)
        files = [os.path.join(target_dir, f) for f in files] # add path to each file
        files.sort(key=lambda x: os.path.getmtime(x))
    for i in range(0,len(files)):
        if i < (len(files)-DASHBOARD_LENGTH):
            print "Deleting",files[i]
            os.unlink(files[i])
    target_dir="vulnerability_reports"
    files = []
    if os.path.exists(target_dir):
        files = os.listdir(target_dir)
        files = [os.path.join(target_dir, f) for f in files] # add path to each file
        files.sort(key=lambda x: os.path.getmtime(x))
    for i in range(0,len(files)):
        if i < (len(files)-DASHBOARD_LENGTH):
            print "Deleting",files[i]
            os.unlink(files[i])

