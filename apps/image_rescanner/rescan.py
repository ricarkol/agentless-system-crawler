#!/usr/bin/env python

import os
import re
from collections import defaultdict

import logging
import logging.handlers
import time
import signal
import sys
import subprocess
import argparse
import datetime
import csv
import requests

#import urllib
#import urllib2
#from urllib2 import Request, urlopen, URLError

try:
    import simplejson as json
except:
    import json

# TODO
#    1. Retrieve all the list of images detected by the reg-monitor and reg-update
#    2. Try to optimize the ES query count for compliance check and vulnerability check. Currently there is one query for each namesapce.
#    3. Keep the state so that images that are already determined to have the scan results are not queried again.
#    4. Limit the rescan retry to a certain number. Need to keep the list and count attempted.
#    5. Refine the sleep time calculation at the end.

################################
### Configuration Parameters ###
################################
loop_sleep_time_per_image=60
reg_update_sleep_time=10 # seconds between each consecutive rescan request within one loop
total_compliance_results=27 # this includes the overall verdict json
logger_file = "/var/log/cloudsight/image_rescanner.log"
log_prefix="rescan_v_007"
################################
################################


def sigterm_handler(signum=None, frame=None):
    print 'Received SIGTERM signal. Goodbye!'
    sys.exit(0)
signal.signal(signal.SIGTERM, sigterm_handler)


if __name__ == '__main__':

    log_dir = os.path.dirname(logger_file)
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)
        os.chmod(log_dir,0755)

    format = '%(asctime)s %(levelname)s %(lineno)s %(funcName)s: %(message)s'
    logging.basicConfig(format=format, level=logging.INFO)
    logger = logging.getLogger(__name__)
    fh = logging.handlers.RotatingFileHandler(logger_file, maxBytes=2<<27, backupCount=4)
    formatter = logging.Formatter(format)
    fh.setFormatter(formatter)
    logger.addHandler(fh)
    logger.propagate = False

    # Suppress the logs from requests module. It was the urllib3 library that produced a log message 
    # for each requests.get call. By setting level to CRITICAL, it is suppressing most of the logs.
    urllib3_logger = logging.getLogger('urllib3')
    urllib3_logger.setLevel(logging.CRITICAL)

    parser = argparse.ArgumentParser(description="")
    parser.add_argument('--elasticsearch-url',  type=str, required=True, help='elasticsearch url: host:port')
    parser.add_argument('--regcrawl1-ip',  type=str, required=True, help='IP address of the REGCRAWL1 host')
    parser.add_argument('--regcrawl2-ip',  type=str, required=True, help='IP address of the REGCRAWL2 host')
    parser.add_argument('--regcrawl3-ip',  type=str, required=True, help='IP address of the REGCRAWL3 host')
    args = parser.parse_args()
    elasticsearch_ip_port = args.elasticsearch_url
    regcrawl1_ip = args.regcrawl1_ip
    regcrawl2_ip = args.regcrawl2_ip
    regcrawl3_ip = args.regcrawl3_ip

    # TODO Need to collect list of namespaces from the registry-monitor and registry-update

    #print elasticsearch_ip_port, regcrawl1_ip, regcrawl2_ip, regcrawl3_ip
    logger.info(log_prefix+" 001 "+elasticsearch_ip_port+" "+regcrawl1_ip+" "+regcrawl2_ip+" "+regcrawl3_ip)
    #time.sleep(5)
    #logger.info("XXXX1-1 regcrawl1_ip:"+regcrawl1_ip)
    #cmd="ssh -o StrictHostKeyChecking=no root@"+regcrawl1_ip+" ls"
    #p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    #ret = ""
    #for line in p.stdout.readlines():
    #    ret = ret+line
    #logger.info("XXXX1-2 "+ret)

    counter=0
    while True:
        logline = ""
        # Retrieve namespaces
        today_str=""
        now = datetime.datetime.now()
        today_str=str(now.year)+"."+str(now.month).zfill(2)+"."+str(now.day-0).zfill(2)
        #today_str="2015.11.05"

        oneday = datetime.timedelta(days=1)
        yesterday = now - oneday
        yesterday_str=str(yesterday.year)+"."+str(yesterday.month).zfill(2)+"."+str(yesterday.day-0).zfill(2)
        #print "Today", today_str 
        #print "Yesterday", yesterday_str

        logger.info(log_prefix+" 002 "+yesterday_str+" "+today_str)

        namespace_list=[]
        ####################################################
        # Build the list of namespaces from config index
        #logger.info("Building namespace list.")
        url = "http://"+elasticsearch_ip_port+"/config-"+yesterday_str+",config-"+today_str+"/_search?pretty=true"
        data = "{ \
                    \"aggs\" : { \
                        \"my_agg\" : { \
                            \"terms\" : { \
                                \"field\" : \"namespace.raw\", \
                                \"size\" : 0 \
                            } \
                        } \
                    }, \
                    \"size\":0 \
                }'"
        response = requests.get(url, data=data)
        if (response.ok):
            #print response.content
            outdata = json.loads(response.content)
            if "error" in outdata.keys():
                logger.error(log_prefix+" Failed to retrieve namespace list data from ES. Idling for 10 minutes.")
                time.sleep(600)
                continue
            # collect list of namespaces in today's config index
            if "aggregations" in outdata.keys() and "my_agg" in outdata["aggregations"] and "buckets" in outdata["aggregations"]["my_agg"]:
                nmspc_dict = outdata["aggregations"]["my_agg"]["buckets"]
                for i in range(0,len(nmspc_dict)):
                    json_str = json.dumps(nmspc_dict[i])
                    json_data = json.loads(json_str)
                    namespace_list.append(json_data["key"])
                    #print json_data["key"]
        else:
            response.raise_for_status()
        #time.sleep(1)
        logger.info(log_prefix+" 003 namespace list collected from config index")
        
        rescan_list=set()
        ####################################################
        # Check compliance results
        #print "Checking for missing compliance scans."
        #logger.info("Checking for missing compliance scans.")
        for nmspc in namespace_list:
            #print nmspc
            url = "http://"+elasticsearch_ip_port+"/compliance-"+yesterday_str+",compliance-"+today_str+"/_search?pretty=true"
            data = "{ \
                    \"query\": { \
                        \"bool\":{ \
                            \"must\":[{ \
                                \"match_phrase_prefix\": { \
                                    \"namespace.raw\" : \""+nmspc+"\" \
                                } \
                            }] \
                        } \
                    }, \
                    \"aggregations\": { \
                        \"my_agg\": { \
                            \"terms\": { \
                                \"field\": \"compliance_id.raw\", \
                                \"size\":0 \
                            } \
                        } \
                    }, \
                \"size\":999999 \
            }'"

            response = requests.get(url, data=data)
            if (response.ok):
                #print response.content
                outdata = json.loads(response.content)
                if "error" in outdata.keys():
                    logger.error(log_prefix+" Failed to retrieve compliance scan data from ES. Idling for 10 minutes.")
                    time.sleep(600)
                    continue
                if "aggregations" in outdata.keys() and "my_agg" in outdata["aggregations"] and "buckets" in outdata["aggregations"]["my_agg"]:
                    comp_result_dict = json.loads(response.content)["aggregations"]["my_agg"]["buckets"]
                    #print "Num of compliance results:",len(comp_result_dict)
                    #for i in range(0,len(comp_result_dict)):
                    #    json_str = json.dumps(comp_result_dict[i])
                    #    json_data = json.loads(json_str)
                    #    print json_data["key"]
                    if len(comp_result_dict)<total_compliance_results:
                        rescan_list.add(nmspc)
                        #print "    ",nmspc,"missing some compliance scan!"
            else:
                response.raise_for_status()

        logger.info(log_prefix+" 004 namespace list collected from compliance index")

        ####################################################
        # Check vulnerability results
        #print "Checking for missing vulnerability scans."
        #logger.info("Checking for missing vulnerability scans.")
        for nmspc in namespace_list:
            url = "http://"+elasticsearch_ip_port+"/vulnerabilityscan-"+yesterday_str+",vulnerabilityscan-"+today_str+"/_count?pretty=true"
            data="{ \
                    \"query\" : { \
                        \"bool\":{ \
                            \"must\":[{ \
                                \"term\" : { \"description.raw\" : \"Overall vulnerability status\" } \
                            },{ \
                                \"term\" : { \"namespace.raw\" : \""+nmspc+"\"} \
                            }] \
                        } \
                    } \
                }'"
            response = requests.get(url, data=data)
            if (response.ok):
                outdata = json.loads(response.content)["count"]
                #print nmspc,outdata
                if int(outdata)<1:
                    rescan_list.add(nmspc)
                    #print "    ",nmspc,"missing vulnerability scan!"
            else:
                response.raise_for_status()
        logger.info(log_prefix+" 005 namespace list collected from vulnerabilityscan index")

        #########################################################
        # Issue rescan command

        # Adding one namespace for testing.
        #rescan_list.add("secreg2.sl.cloud9.ibm.com:5000/btak/btak1202a:latest")

        if len(rescan_list)>0:
            logger.info(log_prefix+" 006 "+log_prefix+" Namespaces detected:"+str(len(namespace_list))+", Rescan needed:"+str(len(rescan_list)))

        rescan_count = 0
        for nm in rescan_list:
            if ":" not in nm:
                #print "Invalid namespace format:",nm
                logger.info(log_prefix+" 007 "+log_prefix+" Skipping since it is an invalid namespace format: "+nm)
                continue

            tag = nm.rsplit(':',1)[1]
            repository = nm.rsplit(':',1)[0]
            logger.info(log_prefix+" 008 "+log_prefix+" Issuing rescan command for "+nm+", repository="+repository+", tag="+tag)
            #print "Rescan target: "+nm+" repository="+repository+" tag="+tag

            url="http://"+regcrawl1_ip+":8000/registry/update"
            data="{ \"repository\":\""+repository+"\",\"tag\":\""+tag+"\"}"
            logger.info(log_prefix+" 009 "+log_prefix+" url="+url+" data="+data)
            response = requests.post(url, data=data)
            if (response.ok):
                #print response.content
                logger.info(log_prefix+" "+response.content)
            else:
                response.raise_for_status()
            rescan_count = rescan_count + 1
            # Between each issue of rescan command, it sleeps some time not to choke the reg update container.
            time.sleep(reg_update_sleep_time)
            
        # Sleep length is dependent upon the number of rescanned images. If there is no image to rescan, it waits 5 min.
        sleep_time = 3600+loop_sleep_time_per_image*rescan_count
        logger.info(log_prefix+" 010 Sleeping "+str(sleep_time)+" seconds. There are "+str(len(namespace_list))+" namespaces.")
        time.sleep(sleep_time)
