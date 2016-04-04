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


    #############################################################
    # Query the Search Service to get the list of new namespaces
    param_begin_time = "begin_time="+btime
    param_end_time = "end_time="+etime
    url = 'http://'+search_service_ip_port+'/namespaces?'+param_begin_time+'&'+param_end_time
    #print url

    data={}
    request = urllib2.Request(url)
    try:
        handler = urllib2.urlopen(request)
        ret = handler.read()
        data = json.loads(ret)
    except URLError as e:
        if hasattr(e, 'reason'):
            print 'INFO No new namespace detected. e.Reason: ', e.reason
        elif hasattr(e, 'code'):
            print 'The server could not fulfill the request. Error code: ', e.code
        exit(0)

    ##################################################################################################
    # I dynamically generate this file (HTML table header) instead of putting it to the report_header.html because columns may change.
    fp = open("report_body_table_header.html","w")
    fp.write("<tr>")
    fp.write("<th align=center rowspan=2><b>Image Name</b></th>")
    fp.write("<th align=center rowspan=2><b>Container ID</b></th>")
    fp.write("<th align=center rowspan=2><b>Crawl Time (UTC)</b></th>")
    fp.write("<th align=center rowspan=2><b>Vulnerability</b></th>")
    fp.write("<th align=center colspan="+str(len(compliance_rule_list))+"><b>ITCS104 Compliance</b>&nbsp;<font size=1><a href=\"http://w3-03.ibm.com/transform/sas/as-web.nsf/ContentDocsByTitle/Linux+Appendix\" target=\"_blank\">(link)</a></font></th>")
    fp.write("</tr>\n")
    fp.write("<tr>\n")
    for k in compliance_rule_list:
        fp.write("<th align=center title=\""+DescriptionDict[k]+"\" width=34px><b>"+k.replace("Linux.","")+"</b></th>")
    fp.write("</tr>\n")
    fp.close()

    #############################################################################################################
    # Make dictionary of time:namespace for all the new namespaces so that I can sort new namespaces by timestamp
    tm_nm_dict=defaultdict(list)
    for item in data.keys(): # iterate over the list of namespaces
        nm_list = data[item]
        for nm in nm_list:

            if nm.startswith("<none>"):
                continue
            param_begin_time = "begin_time="+btime
            param_end_time = "end_time="+etime
            param_namespace = "namespace="+nm
            url = 'http://'+search_service_ip_port+'/namespace/crawl_times?'+param_namespace+'&'+param_begin_time+'&'+param_end_time

            # Get the most recent timestamp
            tm_data={}
            request = urllib2.Request(url)
            try:
                handler = urllib2.urlopen(request)
                ret = handler.read()
                tm_data = json.loads(ret)
            except URLError as e:
                if hasattr(e, 'reason'):
                    print 'Empty data returned. Reason: ', e.reason
                elif hasattr(e, 'code'):
                    print 'The server couldn\'t fulfill the request. Error code: ', e.code

            for j in tm_data.keys():
                tm_list = sorted(tm_data[j])
                tmstr=str(tm_list[len(tm_list)-1]).strip()
                #print tmstr, "\t", nm
                tm_nm_dict[tmstr].append(nm)

    # For one timestamp, there can be multiple namespaces.
    request_id = 0
    status_new_namespace=""
    for tmstr in sorted(tm_nm_dict.keys(),reverse=True):
        for i in range(0,len(tm_nm_dict[tmstr])):
            nm = tm_nm_dict[tmstr][i]
            tm = tmstr
            print tm,nm

            ## Skip if already uncrawled
            mydir = GetUncrawlDirectoryName(nm, tm)
            if mydir=="":
                print "Crawl directory not found. Perhaps already processed."
                continue

            # Skip if crawl time is less than crawl_annotation_report_delay seconds ago
            now = datetime.datetime.utcnow()
            crawltm_adjusted= re.sub("\.[0-9][0-9][0-9]Z", "Z", tm)
            crwl = time.strptime(crawltm_adjusted, "%Y-%m-%dT%H:%M:%SZ")
            crawltm = datetime.datetime(crwl.tm_year, crwl.tm_mon, crwl.tm_mday, crwl.tm_hour, crwl.tm_min, crwl.tm_sec)
            sec_diff = (now-crawltm).total_seconds()
            if sec_diff<crawl_annotation_report_delay:
                print "INFO: Too early to fetch data. It is crawled only "+str(sec_diff)+" seconds ago. Skipping ..."
                if status_new_namespace=="":
                    status_new_namespace=nm.split("/")[0]
                else:
                    status_new_namespace=status_new_namespace+", "+nm.split("/")[0]
                continue
            print "INFO: Time since crawling is "+str(sec_diff)+" seconds."


            # Check if compliance results are available in ES yet.
            cmd="curl --silent -k -XGET http://elastic2-cs.sl.cloud9.ibm.com:9200/compliance-*/_search?pretty -d '{ \"query\": { \"bool\":{ \"must\": [ { \"match_phrase_prefix\": { \"namespace.raw\" : \""+nm+"\" } }, { \"match\": { \"crawled_time\":\""+tm+"\" } } ]}}, \"size\":\"100\" }'"
            p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            ret = ""
            for line in p.stdout.readlines():
                ret = ret+line
            if ret=="":
                print "No compliance results are available. Skipping ..."
                continue
            cmp_data = []
            if ret != "":
                cmp_data = json.loads(ret)["hits"]["hits"]

            if len(cmp_data) < len(compliance_rule_list):
                print "Compliance results are still being indexed. Skipping ..."
                continue


            # Run compliance checking
            with open("report_body.html","a") as report_body:
                report_body.write ("<tr>\n")
                report_body.write("<td align=center>"+nm.split("/")[0]+"</td>\n")
                if len(nm.split("/"))>1:
                    report_body.write("<td align=center>"+nm.split("/")[1]+"</td>\n")
                else:
                    report_body.write("<td></td>\n")
                report_body.write("<td align=center>"+tm.split(".")[0].replace("Z"," ").replace("T"," ")+"</td>\n")

                # Add column for vulnerability
                cmd="curl --silent -k -XGET http://elastic2-cs.sl.cloud9.ibm.com:9200/vulnerabilityscan-*/vulnerabilityscan/_search?pretty -d '{\"query\": { \"bool\":{  \"must\":[    { \"match_phrase_prefix\": { \"namespace.raw\" : \""+nm+"\" } },    { \"match\": { \"timestamp\" : \""+tm+"\" } }  ]}}, \"size\":\"1000\"}'"
                p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                ret = ""
                for line in p.stdout.readlines():
                    ret = ret+line
                vl_data = []
                if ret != "":
                    vl_data = json.loads(ret)["hits"]["hits"]

                # Generate vulnerability report
                vfilename="vulnerability-report-"+str(uuid.uuid4()).replace("-","")+".html"
                fp=open(vfilename,"w")
                fp.write("<html> <head> <style type='text/css'> .myTable { background-color:#FFFFFF;border-collapse:collapse; } .myTable th { background-color:#6B7De7;color:white; font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 13px; } .myTable td, .myTable th { padding:5px;border:1px solid #111111; font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 12px; } </style> </head> <body>")
                fp.write("<a href=\"http://9.2.219.141/kafka-compliance/report.html\"><b>[Return to Main]</b></a>\n")
                fp.write("<br/>\n")
                fp.write("<h3>S&C Service for Docker Cloud: Vulnerability Report</h3>\n")
                fp.write("Image Name: "+nm.split("/")[0]+"\n")
                fp.write("<br/>\n")
                if len(nm.split("/"))>1:
                    fp.write("Container ID: "+nm.split("/")[1]+"\n")
                    fp.write("<br/>\n")
                fp.write("Timestamp: "+tm+"\n")
                fp.write("<br/>\n")
                fp.write("<br/>\n")
                fp.write("<table class=myTable>\n")
                fp.write("<tr><th>USN ID</th><th>Vulnerability Check</th><th>Description</th></tr>\n")
                v_total=0
                v_count=0
                for i in range(0,len(vl_data)):
                    json_str = json.dumps(vl_data[i])
                    json_data = json.loads(json_str)
                    v_usnid     =json_data["_source"]["usnid"]
                    v_timestamp =json_data["_source"]["timestamp"]
                    v_namespace =json_data["_source"]["namespace"]
                    v_summary   =json_data["_source"]["summary"]
                    v_vulnerable=str(json_data["_source"]["vulnerable"]).strip()
                    v_total=v_total+1
                    if v_vulnerable=="True":
                        v_count=v_count+1
                    #print v_usnid, v_timestamp, v_namespace, v_summary, v_vulnerable
                    #fp.write(str(v_usnid)+" "+str(v_timestamp)+" "+str(v_namespace)+" "+str(v_summary)+" "+str(v_vulnerable))
                    fp.write("<tr>")
                    fp.write("<td>"+str(v_usnid)+"</td>")
                    if v_vulnerable=="False":
                        v_vulnerable="Safe"
                    else:
                        v_vulnerable="Vulnerable"

                    if v_vulnerable=="Vulnerable":
                        fp.write("<td align=center style=\"background-color:#ffcccc\"><b><font color=#ff3333>"+str(v_vulnerable)+"</font></b></td>")
                    else:
                        fp.write("<td align=center>"+str(v_vulnerable)+"</td>")
                    fp.write("<td>"+str(v_summary)+"</td>")
                    fp.write("</tr>\n")
                fp.write("</table>")
                fp.write("<br/>")
                fp.write("<a href=\"http://9.2.219.141/kafka-compliance/report.html\"><b>[Return to Main]</b></a>\n")
                fp.write("</body></html>")
                fp.close()

                if v_count>0:
                    report_body.write("<td align=center style=\"background-color:#ffcccc\"><a href=\""+vfilename+"\"><b><font color=#ff3333>"+str(v_count)+"/"+str(v_total)+"</font></b></a></td>\n")
                else:
                    report_body.write("<td align=center><a href=\""+vfilename+"\">"+str(v_count)+"/"+str(v_total)+"</a></td>\n")


            # Run compliance rules. Compliance rule writes the result to report_body.html thru CheckCompliance function.
            # There are also two rules that does not call CheckCompliance, but handles it in its own python file.
            #for k in compliance_rule_list:
            #    #print "    ",k, nm, tm
            #    cmd = "./Comp."+k+".py "+nm+" "+tm+" "+str(request_id)
            #    print "#",cmd
            #    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            #    for line in p.stdout.readlines():
            #        print line.strip()
            #    request_id = request_id + 1


            for cname in compliance_rule_list:
                for i in range(0,len(cmp_data)):
                    json_str = json.dumps(cmp_data[i])
                    json_data = json.loads(json_str)

                    if cname==json_data["_source"]["compliance_id"]:
                        
                        field_compliant=json_data["_source"]["compliant"]
                        with open("report_body.html","a") as myfile:
                            if field_compliant=="true":
                                myfile.write ("<td align=center>Pass</td>")
                            elif field_compliant=="false":
                                myfile.write ("<td align=center style=\"background-color:#ffcccc\"><b><font color=\"#ff3333\">Fail</b></td>")
                            else:
                                myfile.write ("<td align=center >Wait</td>")
                            print cname, json_data["_source"]["compliance_id"], json_data["_source"]["compliant"], field_compliant

            with open("report_body.html","a") as report_body:
                report_body.write ("</tr>\n")

            # Delete uncrawled data
            prefix = GetUncrawlDirectoryName(nm, tm)
            if prefix=="":
                print "WARNING: Uncrawl directory not found!"
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

    body_data_past=""
    if os.path.isfile("report_body_past.html"):
        with open("report_body_past.html","r") as fp:
            body_data_past = fp.read()

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
        fp.write(body_data+"\n"+body_data_past)

    # Get rid of report_body.html now.
    if os.path.isfile("report_body.html"):
        os.unlink("report_body.html")
