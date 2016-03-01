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
import uuid

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
reg_update_sleep_time=1 # seconds between each consecutive rescan request within one loop
total_compliance_results=27 # this includes the overall verdict json
logger_file_name = "image_rescanner.log"
log_prefix="rescan_v_100"
################################
################################


def sigterm_handler(signum=None, frame=None):
    print 'Received SIGTERM signal. Goodbye!'
    sys.exit(0)
signal.signal(signal.SIGTERM, sigterm_handler)


if __name__ == '__main__':

    parser = argparse.ArgumentParser(description="")
    parser.add_argument('--elasticsearch-url',  type=str, required=True, help='elasticsearch url: host:port')
    parser.add_argument('--regcrawl1-ip',  type=str, required=True, help='IP address of the REGCRAWL1 host')
    parser.add_argument('--regcrawl2-ip',  type=str, required=False, default='', help='IP address of the REGCRAWL2 host')
    parser.add_argument('--regcrawl3-ip',  type=str, required=False, default='', help='IP address of the REGCRAWL3 host')
    parser.add_argument('--singlemode',   action='store_true', help='Run one iteration')
    parser.add_argument('--dryrun',  action='store_true', help='Only print out curl command without executing')
    parser.add_argument('--image',  type=str, required=False, default='all', help='Image with tag')
    parser.add_argument('--numdays',  type=int, required=False, default=2, help='Image with tag')
    parser.add_argument('--logdir',  type=str, required=False, default='/var/log/cloudsight', help='directory for log')
    args = parser.parse_args()
    elasticsearch_ip_port = args.elasticsearch_url
    regcrawl1_ip = args.regcrawl1_ip
    regcrawl2_ip = args.regcrawl2_ip
    regcrawl3_ip = args.regcrawl3_ip
    singlemode = args.singlemode
    image = args.image
    numdays = args.numdays
    log_dir = args.logdir
    dryrun = args.dryrun

    if not os.path.exists(log_dir):
        os.makedirs(log_dir)
        os.chmod(log_dir,0755)

    logger_file=os.path.join(log_dir, logger_file_name)
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



    # TODO Need to collect list of namespaces from the registry-monitor and registry-update

    #print elasticsearch_ip_port, regcrawl1_ip, regcrawl2_ip, regcrawl3_ip
    logger.info("======================================================================================")
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
        try:
            logline = ""
            today_str=""
            now = datetime.datetime.now()
            today_str=str(now.year)+"."+str(now.month).zfill(2)+"."+str(now.day-0).zfill(2)
            #today_str="2015.11.05"

            oneday = datetime.timedelta(days=1)

            config_days="config-"+today_str
            compliance_days="compliance-"+today_str
            vulnerability_days="vulnerabilityscan-"+today_str
            newday = now
            for i in range(1,numdays):
                newday = newday - oneday
                newday_str=str(newday.year)+"."+str(newday.month).zfill(2)+"."+str(newday.day-0).zfill(2)
                config_days=config_days+",config-"+newday_str
                compliance_days=compliance_days+",compliance-"+newday_str
                vulnerability_days=vulnerability_days+",vulnerabilityscan-"+newday_str

            logger.info(log_prefix+" 002 "+config_days)
            logger.info(log_prefix+" 002 "+compliance_days)
            logger.info(log_prefix+" 002 "+vulnerability_days)

            namespace_list=[]
            if (image == "all"):
                ####################################################
                # Build the list of namespaces from config index
                #logger.info("Building namespace list.")
                url = "http://"+elasticsearch_ip_port+"/"+config_days+"/_search?pretty=true"
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
                        if singlemode:
                            logger.error(log_prefix+" Failed to retrieve namespace list data from ES.")
                            sys.exit(1)                          
                        else:
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
                logger.info(log_prefix+" 003 namespace list collected from config index: %d images found" % len(namespace_list))
                if singlemode:
                    print (log_prefix+" 003 namespace list collected from config index: %d images found" % len(namespace_list))
            else:
                namespace_list.append(image)

            rescan_list=set()
            ####################################################
            # Check compliance results
            #print "Checking for missing compliance scans."
            #logger.info("Checking for missing compliance scans.")
            compliance_rescan_num = 0
            for nmspc in namespace_list:
                #print nmspc
                url = "http://"+elasticsearch_ip_port+"/"+compliance_days+"/_search?pretty=true"
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
                        if singlemode:
                            logger.error(log_prefix+" Failed to retrieve compliance scan data from ES.")
                            sys.exit(1)
                        else:
                            logger.error(log_prefix+" Failed to retrieve compliance scan data from ES. Idling for 10 minutes.")
                            time.sleep(600)
                            continue
                    if "aggregations" in outdata.keys() and "my_agg" in outdata["aggregations"] and "buckets" in outdata["aggregations"]["my_agg"]:
                        comp_result_dict = json.loads(response.content)["aggregations"]["my_agg"]["buckets"]
                        #for i in range(0,len(comp_result_dict)):
                        #    json_str = json.dumps(comp_result_dict[i])
                        #    json_data = json.loads(json_str)
                        #    print json_data["key"]
                        if len(comp_result_dict)<total_compliance_results:
                            rescan_list.add(nmspc)
                            compliance_rescan_num = compliance_rescan_num + 1
                            logger.info("%s missing some compliance scan! Only %d found" % (nmspc, len(comp_result_dict)))
                        else:
                            logger.info("%s compliance scan OK" % nmspc)

                else:
                    response.raise_for_status()

            logger.info(log_prefix+" 004 namespace list collected from compliance index %d images to rescan" % compliance_rescan_num)
            if singlemode:
                print(log_prefix+" 004 namespace list collected from compliance index %d images to rescan" % compliance_rescan_num)

            ####################################################
            # Check vulnerability results
            #print "Checking for missing vulnerability scans."
            #logger.info("Checking for missing vulnerability scans.")
            vulnerability_rescan_num = 0
            for nmspc in namespace_list:
                url = "http://"+elasticsearch_ip_port+"/"+vulnerability_days+"/_count?pretty=true"
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
                        vulnerability_rescan_num = vulnerability_rescan_num + 1
                        logger.info("%s missing vulnerability scan!" % nmspc)
                    else:
                        logger.info("%s vulnerability scan OK" % nmspc)
                else:
                    response.raise_for_status()

            logger.info(log_prefix+" 005 namespace list collected from vulnerabilityscan index %d images to rescan" % vulnerability_rescan_num)
            if singlemode:
                print(log_prefix+" 005 namespace list collected from vulnerabilityscan index %d images to rescan" % vulnerability_rescan_num)

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
                logger.info(log_prefix+" 008 "+log_prefix+" Preparing rescan command for "+nm+", repository="+repository+", tag="+tag)
                #print "Rescan target: "+nm+" repository="+repository+" tag="+tag

                # We have to make up an id for registry-update as it expects one from the registry
                dummy_id = str(uuid.uuid1())

                url="http://"+regcrawl1_ip+":8000/registry/update"
                data="{ \"repository\":\""+repository+"\",\"tag\":\""+tag+"\",\"id\":\""+dummy_id+"\"}"
                headers={'Accept': 'application/json', 'Content-Type': 'application/json'}
                logger.info(log_prefix+" 009 "+log_prefix+" url="+url+" data="+data)
                if dryrun:
                    logger.info("curl --silent -v -XPOST -H 'Content-Type: application/json' -d '{\"repository\": \"%s\", \"tag\": \"%s\", \"id\": \"%s\"}' http://localhost:8000/registry/update" % (repository, tag, dummy_id))
                else:
                    response = requests.post(url, data=data, headers=headers)
                    if (response.ok):
                        #print response.content
                        logger.info(log_prefix+" "+response.content)
                    else:
                        response.raise_for_status()
                    rescan_count = rescan_count + 1
                    # Between each issue of rescan command, it sleeps some time not to choke the reg update container.
                    time.sleep(reg_update_sleep_time)
                
        except Exception as e:
            logger.info('Rescanner exception %s. Sleeping for a minute then restarting' % str(e))
            time.sleep(60)

        if singlemode:
            break

        # Sleep length is dependent upon the number of rescanned images. If there is no image to rescan, it waits 5 min.
        sleep_time = 3600+loop_sleep_time_per_image*rescan_count
        logger.info(log_prefix+" 010 Sleeping "+str(sleep_time)+" seconds. There are "+str(len(namespace_list))+" namespaces.")
        time.sleep(sleep_time)


