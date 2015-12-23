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

import urllib
import urllib2
from urllib2 import Request, urlopen, URLError

try:
    import simplejson as json
except:
    import json

##########################################
# Update this number to differentiate logs
version_code="KPI_v_032"
since_date="2015-09-06T00:00:00"
##########################################

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
    "Linux.20-0-b",
    "Linux.20-0-c",
]

logger_file = "/var/log/cloudsight/vastat_reporter.log"

def sigterm_handler(signum=None, frame=None):
    print 'Received SIGTERM signal. Goodbye!'
    sys.exit(0)
signal.signal(signal.SIGTERM, sigterm_handler)

def GetStatistic(cnt):
    dates=[]
    now = datetime.datetime.now()
    dates.append(str(now.year)+"."+str(now.month).zfill(2)+"."+str(now.day-0).zfill(2))
    dates_string = dates[0]
    for i in range(1,len(dates)):
        dates_string = dates_string + "," + dates[i]
    dates_string="*"
    log_line=""

    version_number = "_asdf001_"
    logger.info("vastat "+version_number+" ("+str(cnt)+") 01 Entering GetStatistic")


    #############################################################
    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-"+dates_string+"/_search?pretty -d '{ \
            \"query\": { \
                \"bool\":{ \
                    \"must\":[{ \
                        \"match_phrase_prefix\": { \
                            \"compliant.raw\" : \"true\" \
                        } \
                    } \
                    ] \
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
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    outdata = []
    if ret != "":
        logger.info("vastat "+version_number+" ("+str(cnt)+") 02 curl command returned non-emtpy results")
        outdata = json.loads(ret)["aggregations"]["my_agg"]["buckets"]

        count_str=""
        for i in range(0,len(compliance_rule_list)):
            current_rule_id = compliance_rule_list[i]
            current_count = 0

            for j in range(0,len(outdata)):
                json_str = json.dumps(outdata[j])
                json_data = json.loads(json_str)
                #print json_data["key"], json_data["doc_count"]
                if json_data["key"]==current_rule_id:
                    current_count = json_data["doc_count"]
            count_str = count_str + " " + str(current_count)
        #print "T"+count_str
        #logger.info("vastat T"+count_str)
        log_line = "vastat "+version_number+" ("+str(cnt)+") 99 T"+count_str

    logger.info("vastat "+version_number+" ("+str(cnt)+") 03 Obtained True compliance results")

    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-"+dates_string+"/_search?pretty -d '{ \
            \"query\": { \
                \"bool\":{ \
                    \"must\":[{ \
                        \"match_phrase_prefix\": { \
                            \"compliant.raw\" : \"false\" \
                        } \
                    } \
                    ] \
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
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    outdata = []
    if ret != "":
        logger.info("vastat "+version_number+" ("+str(cnt)+") 04 curl command returned non-emtpy results")
        outdata = json.loads(ret)["aggregations"]["my_agg"]["buckets"]

        count_str=""
        for i in range(0,len(compliance_rule_list)):
            current_rule_id = compliance_rule_list[i]
            current_count = 0

            for j in range(0,len(outdata)):
                json_str = json.dumps(outdata[j])
                json_data = json.loads(json_str)
                #print json_data["key"], json_data["doc_count"]
                if json_data["key"]==current_rule_id:
                    current_count = json_data["doc_count"]
            count_str = count_str + " " + str(current_count)
        #print "F"+count_str
        #logger.info("vastat F"+count_str)
        log_line = log_line + " F" + count_str

    logger.info("vastat "+version_number+" ("+str(cnt)+") 05 Obtained True compliance results")

    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/vulnerabilityscan-"+dates_string+"/vulnerabilityscan/_search?pretty -d '{ \
        \"query\": { \
            \"bool\":{ \
                \"must\": \
                    [ { \
                        \"match_phrase_prefix\": { \
                            \"description\" : \"Overall vulnerability status\" \
                        } \
                    } ] \
            } \
        }, \
        \"size\":\"999999999\" \
    }' "
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    outdata = []
    if ret != "":
        logger.info("vastat "+version_number+" ("+str(cnt)+") 06 curl command returned non-emtpy results")
        outdata = json.loads(ret)["hits"]["hits"]
        false_count = 0
        true_count = 0
        sum_total_packages=0
        min_num_packages=999999999
        max_num_packages=0
        sum_vulnerable_usns=0
        sum_uncrawlable=0
        for i in range(0,len(outdata)):
            json_str = json.dumps(outdata[i])
            json_data = json.loads(json_str)

            sum_total_packages = sum_total_packages + json_data["_source"]["total_packages"]
            sum_vulnerable_usns = sum_vulnerable_usns + json_data["_source"]["vulnerable_usns"]

            if json_data["_source"]["vulnerable_packages"] == -1:
                sum_uncrawlable = sum_uncrawlable + 1

            if json_data["_source"]["total_packages"] > max_num_packages:
                max_num_packages = json_data["_source"]["total_packages"]

            if json_data["_source"]["total_packages"] < min_num_packages:
                min_num_packages = json_data["_source"]["total_packages"]

            if "false"==json_data["_source"]["vulnerable"]:
                false_count = false_count + 1
            else:
                true_count = true_count + 1
    logger.info("vastat "+version_number+" ("+str(cnt)+") 07 Obtained True compliance results")

    #print "V "+str(true_count)+" "+str(false_count)+" "+str(min_num_packages)+" "+str(max_num_packages)+" "+str(sum_uncrawlable)
    #logger.info("vastat V "+str(true_count)+" "+str(false_count)+" "+str(min_num_packages)+" "+str(max_num_packages)+" "+str(sum_uncrawlable))
    log_line = log_line + " V "+str(true_count)+" "+str(false_count)+" "+str(min_num_packages)+" "+str(max_num_packages)+" "+str(sum_uncrawlable)

    logger.info(log_line)

def GetUniqueNamespaceCount():
    cmd="curl --silent -XPOST 'http://"+elasticsearch_ip_port+"/config-*/_search?pretty' -d '{ \
            \"aggs\" : { \
                \"namespace_count\" : { \
                    \"cardinality\" : { \
                        \"field\" : \"namespace.raw\" \
                    } \
                } \
            }, \
            \"size\":0 \
        }'"

    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["aggregations"]["namespace_count"]["value"]
        return outdata
    return -1

def GetOverallComplianceFalseCount(dates_string):
    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-"+dates_string+"/_search?pretty -d '{ \
            \"query\": { \
                \"bool\":{ \
                    \"must\":[{ \
                        \"match_phrase_prefix\": { \
                            \"compliant.raw\" : \"false\" \
                        } \
                    } \
                    ] \
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
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["aggregations"]["my_agg"]["buckets"]
        count_str=""

        current_rule_id = "Linux.0-0-a"
        current_count = 0
        for j in range(0,len(outdata)):
            json_str = json.dumps(outdata[j])
            json_data = json.loads(json_str)
            #print json_data["key"], json_data["doc_count"]
            if json_data["key"]==current_rule_id:
                current_count = json_data["doc_count"]
        count_str = count_str + str(current_count) + " "

        return count_str
    else:
        return -1

def GetOverallComplianceTrueCount(dates_string):
    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-"+dates_string+"/_search?pretty -d '{ \
            \"query\": { \
                \"bool\":{ \
                    \"must\":[{ \
                        \"match_phrase_prefix\": { \
                            \"compliant.raw\" : \"true\" \
                        } \
                    } \
                    ] \
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
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["aggregations"]["my_agg"]["buckets"]
        count_str=""

        current_rule_id = "Linux.0-0-a"
        current_count = 0
        for j in range(0,len(outdata)):
            json_str = json.dumps(outdata[j])
            json_data = json.loads(json_str)
            #print json_data["key"], json_data["doc_count"]
            if json_data["key"]==current_rule_id:
                current_count = json_data["doc_count"]
        count_str = count_str + str(current_count) + " "

        return count_str
    else:
        return -1


def GetComplianceFalseCountByRule(dates_string):
    #cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-"+dates_string+"/_search?pretty -d '{ \
    #        \"query\": { \
    #            \"bool\":{ \
    #                \"must\":[{ \
    #                    \"match_phrase_prefix\": { \
    #                        \"compliant.raw\" : \"false\" \
    #                    } \
    #                } \
    #                ] \
    #            } \
    #        }, \
    #        \"aggregations\": { \
    #            \"my_agg\": { \
    #                \"terms\": { \
    #                    \"field\": \"compliance_id.raw\", \
    #                    \"size\":0 \
    #                } \
    #            } \
    #        }, \
    #        \"size\":1 \
    #    }'"
    #p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    #ret = ""
    #for line in p.stdout.readlines():
    #    ret = ret+line
    #if ret != "":
    #    outdata = json.loads(ret)["aggregations"]["my_agg"]["buckets"]
    #    count_str=""
    #    for i in range(0,len(compliance_rule_list)):
    #        current_rule_id = compliance_rule_list[i]
    #        current_count = 0
    #        for j in range(0,len(outdata)):
    #            json_str = json.dumps(outdata[j])
    #            json_data = json.loads(json_str)
    #            #print json_data["key"], json_data["doc_count"]
    #            if json_data["key"]==current_rule_id:
    #                current_count = json_data["doc_count"]
    #        count_str = count_str + str(current_count) + " "
    #    return count_str
    #else:
    #    return -1

    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-*/compliance/_search?pretty -d ' \
        { \
            \"query\": { \
                \"bool\":{ \
                    \"must\":[{ \
                        \"term\": { \"compliant.raw\" : \"false\" } \
                    }] \
                } \
            }, \
            \"aggs\": { \
                \"my_filter\": { \
                    \"filter\": { \
                        \"range\": { \
                            \"crawled_time\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }, \
                    \"aggs\": { \
                        \"my_agg\": { \
                            \"terms\": { \
                                \"field\": \"compliance_id.raw\", \
                                \"size\":0 \
                            } \
                        } \
                    } \
                } \
            }, \
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["aggregations"]["my_filter"]["my_agg"]["buckets"]
        count_str=""
        for i in range(0,len(compliance_rule_list)):
            current_rule_id = compliance_rule_list[i]
            current_count = 0

            for j in range(0,len(outdata)):
                json_str = json.dumps(outdata[j])
                json_data = json.loads(json_str)
                #print json_data["key"], json_data["doc_count"]
                if json_data["key"]==current_rule_id:
                    current_count = json_data["doc_count"]
            count_str = count_str + str(current_count) + " "
        return count_str
    else:
        return -1

def GetComplianceFalseCountByRule_icetest1(dates_string):

    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-*/compliance/_search?pretty -d ' \
        { \
            \"query\": { \
                \"bool\":{ \
                    \"must\":[{ \
                        \"term\": { \"compliant.raw\" : \"false\" } \
                    }] \
                } \
            }, \
            \"aggs\": { \
                \"my_filter\": { \
                    \"filter\": { \
                        \"range\": { \
                            \"crawled_time\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }, \
                    \"aggs\": { \
                        \"my_agg\": { \
                            \"terms\": { \
                                \"field\": \"compliance_id.raw\", \
                                \"size\":0 \
                            } \
                        } \
                    } \
                } \
            }, \
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line

    # get data for icetest1 image
    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-*/compliance/_search?pretty -d ' \
        { \
            \"query\": { \
                \"bool\":{ \
                    \"must\":[{ \
                        \"term\": { \"compliant.raw\" : \"false\" } \
                    },{ \
                        \"term\" : { \"namespace.raw\" : \"registry.ng.bluemix.net/icetest1/hello-test:latest\"} \
                    }] \
                } \
            }, \
            \"aggs\": { \
                \"my_filter\": { \
                    \"filter\": { \
                        \"range\": { \
                            \"crawled_time\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }, \
                    \"aggs\": { \
                        \"my_agg\": { \
                            \"terms\": { \
                                \"field\": \"compliance_id.raw\", \
                                \"size\":0 \
                            } \
                        } \
                    } \
                } \
            }, \
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret_icetest1 = ""
    for line in p.stdout.readlines():
        ret_icetest1 = ret_icetest1 + line


    if ret != "":
        outdata = json.loads(ret)["aggregations"]["my_filter"]["my_agg"]["buckets"]
        outdata_icetest1 = json.loads(ret_icetest1)["aggregations"]["my_filter"]["my_agg"]["buckets"]
        count_str=""
        for i in range(0,len(compliance_rule_list)):
            current_rule_id = compliance_rule_list[i]

            current_count = 0
            for j in range(0,len(outdata)):
                json_str = json.dumps(outdata[j])
                json_data = json.loads(json_str)
                if json_data["key"]==current_rule_id:
                    current_count = json_data["doc_count"]

            current_count_icetest1 = 0
            for j in range(0,len(outdata_icetest1)):
                json_str = json.dumps(outdata_icetest1[j])
                json_data = json.loads(json_str)
                if json_data["key"]==current_rule_id:
                    current_count_icetest1 = json_data["doc_count"]

            current_count = current_count - current_count_icetest1

            count_str = count_str + str(current_count) + " "
        return count_str
    else:
        return -1


def GetComplianceTrueCountByRule(dates_string):
    #cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-"+dates_string+"/_search?pretty -d '{ \
    #        \"query\": { \
    #            \"bool\":{ \
    #                \"must\":[{ \
    #                    \"match_phrase_prefix\": { \
    #                        \"compliant.raw\" : \"true\" \
    #                    } \
    #                } \
    #                ] \
    #            } \
    #        }, \
    #        \"aggregations\": { \
    #            \"my_agg\": { \
    #                \"terms\": { \
    #                    \"field\": \"compliance_id.raw\", \
    #                    \"size\":0 \
    #                } \
    #            } \
    #        }, \
    #        \"size\":1 \
    #    }'"
    #p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    #ret = ""
    #for line in p.stdout.readlines():
    #    ret = ret+line
    #if ret != "":
    #    outdata = json.loads(ret)["aggregations"]["my_agg"]["buckets"]
    #    count_str=""
    #    for i in range(0,len(compliance_rule_list)):
    #        current_rule_id = compliance_rule_list[i]
    #        current_count = 0
    #
    #        for j in range(0,len(outdata)):
    #            json_str = json.dumps(outdata[j])
    #            json_data = json.loads(json_str)
    #            #print json_data["key"], json_data["doc_count"]
    #            if json_data["key"]==current_rule_id:
    #                current_count = json_data["doc_count"]
    #        count_str = count_str + str(current_count) + " "
    #    return count_str
    #else:
    #    return -1

    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-*/compliance/_search?pretty -d ' \
        { \
            \"query\": { \
                \"bool\":{ \
                    \"must\":[{ \
                        \"term\": { \"compliant.raw\" : \"true\" } \
                    }] \
                } \
            }, \
            \"aggs\": { \
                \"my_filter\": { \
                    \"filter\": { \
                        \"range\": { \
                            \"crawled_time\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }, \
                    \"aggs\": { \
                        \"my_agg\": { \
                            \"terms\": { \
                                \"field\": \"compliance_id.raw\", \
                                \"size\":0 \
                            } \
                        } \
                    } \
                } \
            }, \
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["aggregations"]["my_filter"]["my_agg"]["buckets"]
        count_str=""
        for i in range(0,len(compliance_rule_list)):
            current_rule_id = compliance_rule_list[i]
            current_count = 0
    
            for j in range(0,len(outdata)):
                json_str = json.dumps(outdata[j])
                json_data = json.loads(json_str)
                #print json_data["key"], json_data["doc_count"]
                if json_data["key"]==current_rule_id:
                    current_count = json_data["doc_count"]
            count_str = count_str + str(current_count) + " "
        return count_str
    else:
        return -1



def GetComplianceTrueCountByRule_icetest1(dates_string):

    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-*/compliance/_search?pretty -d ' \
        { \
            \"query\": { \
                \"bool\":{ \
                    \"must\":[{ \
                        \"term\": { \"compliant.raw\" : \"true\" } \
                    }] \
                } \
            }, \
            \"aggs\": { \
                \"my_filter\": { \
                    \"filter\": { \
                        \"range\": { \
                            \"crawled_time\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }, \
                    \"aggs\": { \
                        \"my_agg\": { \
                            \"terms\": { \
                                \"field\": \"compliance_id.raw\", \
                                \"size\":0 \
                            } \
                        } \
                    } \
                } \
            }, \
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line

    # get data for icetest1 image
    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-*/compliance/_search?pretty -d ' \
        { \
            \"query\": { \
                \"bool\":{ \
                    \"must\":[{ \
                        \"term\": { \"compliant.raw\" : \"true\" } \
                    },{ \
                        \"term\" : { \"namespace.raw\" : \"registry.ng.bluemix.net/icetest1/hello-test:latest\"} \
                    }] \
                } \
            }, \
            \"aggs\": { \
                \"my_filter\": { \
                    \"filter\": { \
                        \"range\": { \
                            \"crawled_time\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }, \
                    \"aggs\": { \
                        \"my_agg\": { \
                            \"terms\": { \
                                \"field\": \"compliance_id.raw\", \
                                \"size\":0 \
                            } \
                        } \
                    } \
                } \
            }, \
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret_icetest1 = ""
    for line in p.stdout.readlines():
        ret_icetest1 = ret_icetest1 + line

    if ret != "":
        outdata = json.loads(ret)["aggregations"]["my_filter"]["my_agg"]["buckets"]
        outdata_icetest1 = json.loads(ret_icetest1)["aggregations"]["my_filter"]["my_agg"]["buckets"]
        count_str=""
        for i in range(0,len(compliance_rule_list)):
            current_rule_id = compliance_rule_list[i]

            current_count = 0
            for j in range(0,len(outdata)):

                json_str = json.dumps(outdata[j])
                json_data = json.loads(json_str)
                if json_data["key"]==current_rule_id:
                    current_count = json_data["doc_count"]

            current_count_icetest1 = 0
            for j in range(0,len(outdata_icetest1)):
                json_str = json.dumps(outdata_icetest1[j])
                json_data = json.loads(json_str)
                if json_data["key"]==current_rule_id:
                    current_count_icetest1 = json_data["doc_count"]

            current_count = current_count - current_count_icetest1

            count_str = count_str + str(current_count) + " "
        return count_str
    else:
        return -1


def GetVulnerableCount():
    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/vulnerabilityscan-*/vulnerabilityscan/_search?pretty -d '{ \
        \"query\": { \
            \"bool\":{ \
                \"must\":[{ \
                    \"match_phrase_prefix\": { \
                        \"description.raw\" : \"Overall vulnerability status\" \
                    } \
                }] \
            } \
        }, \
        \"aggregations\": { \
            \"my_agg\": { \
                \"terms\": { \
                    \"field\": \"vulnerable\", \
                    \"size\":0 \
                } \
            } \
        }, \
        \"size\":\"1\" \
    }'"

    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        count_str=""
        outdata = json.loads(ret)["aggregations"]["my_agg"]["buckets"]
        for j in range(0,len(outdata)):
            json_str = json.dumps(outdata[j])
            json_data = json.loads(json_str)
            #print json_data["key"], json_data["doc_count"]
            if json_data["key"]=="T":
                current_count = json_data["doc_count"]
        count_str = count_str + str(current_count) + " "

        for j in range(0,len(outdata)):
            json_str = json.dumps(outdata[j])
            json_data = json.loads(json_str)
            #print json_data["key"], json_data["doc_count"]
            if json_data["key"]=="F":
                current_count = json_data["doc_count"]
        count_str = count_str + str(current_count) + " "
        return count_str
    else: 
        return -1


def GetImageCrawlCount():

    cmd="curl --silent -XPOST 'http://"+elasticsearch_ip_port+"/config-*/_search?pretty' -d '{ \
        \"query\": { \
            \"bool\":{ \
                \"must\":[{ \
                    \"match_phrase_prefix\": { \
                        \"feature_type.raw\" : \"os\" \
                    } \
                } \
                ] \
            } \
        }, \
        \"size\":999999999 \
    }'" \


    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    outdata = []
    if ret != "":

        f = open ("/tmp/_tmp02894", 'w')

        outdata = json.loads(ret)["hits"]["hits"]
        for i in range(0,len(outdata)):
            json_str = json.dumps(outdata[i])
            json_data = json.loads(json_str)

            f.write(json_data["_source"]["namespace"]+json_data["_source"]["container_image"]+"\n")

        f.close()

    outstr=""
    # Number of lines 
    #cmd="cat /tmp/_tmp02894 | wc -l"
    #p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    #ret = ""
    #for line in p.stdout.readlines():
    #    ret = ret+line
    #outstr = outstr + ret.strip()

    # Number of lines after sorting/unique
    cmd="sort -u /tmp/_tmp02894 | wc -l"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    outstr = outstr + " " + ret.strip()

    os.remove("/tmp/_tmp02894")
    return outstr

def GetVulnerablePackageDistribution():
    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/vulnerabilityscan-*/vulnerabilityscan/_search?pretty -d '{ \
      \"aggs\": { \
        \"group_by_vulnerable\": { \
          \"terms\": { \
            \"field\": \"vulnerable_packages\" \
          } \
        } \
      }, \
      \"size\": 1 \
    }'"

    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["aggregations"]["group_by_vulnerable"]["buckets"]
        count_str=""

        supported_cnt = 0
        unsupported_cnt = 0
        for j in range(0,len(outdata)):
            json_str = json.dumps(outdata[j])
            json_data = json.loads(json_str)
            #print json_data["key"], json_data["doc_count"]
            if json_data["key"]==-1:
                unsupported_cnt = json_data["doc_count"]
            else:
                supported_cnt = supported_cnt + json_data["doc_count"]

        count_str = str(supported_cnt) + " " + str(unsupported_cnt)
        return count_str
    else:
        return -1

def GetImagePushCount(dates_string):
#    cmd="curl --silent -XPOST 'http://"+elasticsearch_ip_port+"/config-"+dates_string+"/_count?pretty' -d '{ \
#            \"query\": { \
#                \"bool\":{ \
#                    \"must\":[{ \
#                        \"match_phrase_prefix\": { \
#                            \"feature_type.raw\" : \"os\" \
#                        } \
#                    }] \
#                } \
#            } \
#        }'"
#    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
#    ret = ""
#    for line in p.stdout.readlines():
#        ret = ret+line
#    if ret != "":
#        outdata = json.loads(ret)["count"]
#        return outdata

    cmd="curl --silent -XPOST 'http://"+elasticsearch_ip_port+"/config-"+dates_string+"/_search?pretty' -d '{ \
                \"query\": { \
                    \"bool\":{ \
                        \"must\":[{ \
                            \"match_phrase_prefix\": { \
                                \"feature_type.raw\" : \"os\" \
                            } \
                        }] \
                    } \
                }, \
                \"filter\": { \
                    \"bool\": { \
                        \"must\": [{ \
                            \"range\": { \
                                \"timestamp\": { \
                                    \"gt\" : \""+since_date+"\" \
                                } \
                            } \
                        }] \
                    } \
                }, \
                \"size\":1 \
            }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["hits"]["total"]
        return outdata
    return -1

def GetImagePushCount_icetest1(dates_string):

    cmd="curl --silent -XPOST 'http://"+elasticsearch_ip_port+"/config-"+dates_string+"/_search?pretty' -d '{ \
                \"query\": { \
                    \"bool\":{ \
                        \"must\":[{ \
                            \"term\" : { \"feature_type.raw\" : \"os\" } \
                        },{ \
                            \"term\" : { \"namespace.raw\" : \"registry.ng.bluemix.net/icetest1/hello-test:latest\"} \
                        }] \
                    } \
                }, \
                \"filter\": { \
                    \"bool\": { \
                        \"must\": [{ \
                            \"range\": { \
                                \"timestamp\": { \
                                    \"gt\" : \""+since_date+"\" \
                                } \
                            } \
                        }] \
                    } \
                }, \
                \"size\":1 \
            }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["hits"]["total"]
        return outdata
    return -1

def GetVulnerabilityScanStat(dates_string):

    #cmd="curl --silent -k -XPOST 'http://"+elasticsearch_ip_port+"/vulnerabilityscan-"+dates_string+"/vulnerabilityscan/_count?pretty' -d ' \
    #    { \"query\" : { \
    #        \"term\" : { \"description.raw\" : \"Overall vulnerability status\" } \
    #    }}'"
    #p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    #ret = ""
    #for line in p.stdout.readlines():
    #    ret = ret+line
    #if ret != "":
    #    outdata = json.loads(ret)["count"]
    #    return outdata

    cmd="curl --silent -k -XPOST 'http://"+elasticsearch_ip_port+"/vulnerabilityscan-*/vulnerabilityscan/_search?pretty' -d ' \
    { \
        \"query\" : { \
            \"term\" : { \"description.raw\" : \"Overall vulnerability status\" } \
        }, \
        \"filter\": { \
            \"bool\": { \
                \"must\": [{ \
                    \"range\": { \
                        \"timestamp\" : { \
                            \"gt\" : \""+since_date+"\" \
                        } \
                    } \
                }] \
            } \
        }, \
        \"size\":1 \
    }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["hits"]["total"]
        return outdata
    return -1


def GetVulnerabilityScanStat_icetest1(dates_string):

    cmd="curl --silent -k -XPOST 'http://"+elasticsearch_ip_port+"/vulnerabilityscan-*/vulnerabilityscan/_search?pretty' -d ' \
    { \
        \"query\" : { \
                    \"bool\":{ \
                        \"must\":[{ \
                            \"term\" : { \"description.raw\" : \"Overall vulnerability status\" } \
                        },{ \
                            \"term\" : { \"namespace.raw\" : \"registry.ng.bluemix.net/icetest1/hello-test:latest\"} \
                        }] \
                    } \
        }, \
        \"filter\": { \
            \"bool\": { \
                \"must\": [{ \
                    \"range\": { \
                        \"timestamp\" : { \
                            \"gt\" : \""+since_date+"\" \
                        } \
                    } \
                }] \
            } \
        }, \
        \"size\":1 \
    }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["hits"]["total"]
        return outdata
    return -1


def GetVulnerabilityFalseCount(dates_string):

    #cmd="curl --silent -k -XPOST 'http://"+elasticsearch_ip_port+"/vulnerabilityscan-"+dates_string+"/vulnerabilityscan/_count?pretty' -d ' \
    #    { \"query\": { \
    #            \"bool\": { \
    #                \"must\" :[{ \
    #                    \"term\" : { \"description.raw\" : \"Overall vulnerability status\" } \
    #                },{ \
    #                    \"term\" : { \"vulnerable\" : false } \
    #                }] \
    #            } \
    #        } \
    #    }'"
    #p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    #ret = ""
    #for line in p.stdout.readlines():
    #    ret = ret+line
    #if ret != "":
    #    outdata = json.loads(ret)["count"]
    #    return outdata

    cmd="curl --silent -k -XPOST 'http://"+elasticsearch_ip_port+"/vulnerabilityscan-*/vulnerabilityscan/_search?pretty' -d ' \
        { \
            \"query\": { \
                \"bool\": { \
                    \"must\" :[{ \
                        \"term\" : { \"description.raw\" : \"Overall vulnerability status\" } \
                    },{ \
                        \"term\" : { \"vulnerable\" : false } \
                    }] \
                } \
            }, \
            \"filter\": { \
                \"bool\": { \
                    \"must\": [{ \
                        \"range\": { \
                            \"timestamp\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }] \
                } \
            }, \
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["hits"]["total"]
        return outdata
    return -1


def GetVulnerabilityFalseCount_icetest1(dates_string):

    cmd="curl --silent -k -XPOST 'http://"+elasticsearch_ip_port+"/vulnerabilityscan-*/vulnerabilityscan/_search?pretty' -d ' \
        { \
            \"query\": { \
                \"bool\": { \
                    \"must\" :[{ \
                        \"term\" : { \"description.raw\" : \"Overall vulnerability status\" } \
                    },{ \
                        \"term\" : { \"vulnerable\" : false } \
                    },{ \
                        \"term\" : { \"namespace.raw\" : \"registry.ng.bluemix.net/icetest1/hello-test:latest\"} \
                    }] \
                } \
            }, \
            \"filter\": { \
                \"bool\": { \
                    \"must\": [{ \
                        \"range\": { \
                            \"timestamp\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }] \
                } \
            }, \
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["hits"]["total"]
        return outdata
    return -1


def GetVulnerabilityTrueCount(dates_string):

    #cmd="curl --silent -k -XPOST 'http://"+elasticsearch_ip_port+"/vulnerabilityscan-"+dates_string+"/vulnerabilityscan/_count?pretty' -d ' \
    #    { \"query\": { \
    #            \"bool\": { \
    #                \"must\" :[{ \
    #                    \"term\" : { \"description.raw\" : \"Overall vulnerability status\" } \
    #                },{ \
    #                    \"term\" : { \"vulnerable\" : true} \
    #                }] \
    #            } \
    #        } \
    #    }'"
    #p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    #ret = ""
    #for line in p.stdout.readlines():
    #    ret = ret+line
    #if ret != "":
    #    outdata = json.loads(ret)["count"]
    #    return outdata

    cmd="curl --silent -k -XPOST 'http://"+elasticsearch_ip_port+"/vulnerabilityscan-*/vulnerabilityscan/_search?pretty' -d ' \
        { \
            \"query\": { \
                \"bool\": { \
                    \"must\" :[{ \
                        \"term\" : { \"description.raw\" : \"Overall vulnerability status\" } \
                    },{ \
                        \"term\" : { \"vulnerable\" : true } \
                    }] \
                } \
            }, \
            \"filter\": { \
                \"bool\": { \
                    \"must\": [{ \
                        \"range\": { \
                            \"timestamp\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }] \
                } \
            }, \
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["hits"]["total"]
        return outdata
    return -1

def GetVulnerabilityTrueCount_icetest1(dates_string):

    cmd="curl --silent -k -XPOST 'http://"+elasticsearch_ip_port+"/vulnerabilityscan-*/vulnerabilityscan/_search?pretty' -d ' \
        { \
            \"query\": { \
                \"bool\": { \
                    \"must\" :[{ \
                        \"term\" : { \"description.raw\" : \"Overall vulnerability status\" } \
                    },{ \
                        \"term\" : { \"vulnerable\" : true } \
                    },{ \
                        \"term\" : { \"namespace.raw\" : \"registry.ng.bluemix.net/icetest1/hello-test:latest\"} \
                    }] \
                } \
            }, \
            \"filter\": { \
                \"bool\": { \
                    \"must\": [{ \
                        \"range\": { \
                            \"timestamp\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }] \
                } \
            }, \
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["hits"]["total"]
        return outdata
    return -1


def GetComplianceScanStat(dates_string):

    #cmd="curl --silent -k -XPOST 'http://"+elasticsearch_ip_port+"/compliance-"+dates_string+"/_count?pretty' -d ' \
    #    { \"query\": { \
    #        \"term\" : { \"compliance_id.raw\" : \"Linux.0-0-a\" } \
    #    }}'"
    #p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    #ret = ""
    #for line in p.stdout.readlines():
    #    ret = ret+line
    #if ret != "":
    #    outdata = json.loads(ret)["count"]
    #    return outdata

    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-*/compliance/_search?pretty -d ' \
        { \
            \"query\": { \
                \"term\" : { \"compliance_id.raw\" : \"Linux.0-0-a\" } \
            }, \
            \"filter\": { \
                \"bool\": { \
                    \"must\": [{ \
                        \"range\": { \
                            \"crawled_time\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }] \
                } \
            }, \
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["hits"]["total"]
        return outdata
    return -1


def GetComplianceScanStat_icetest1(dates_string):

    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-*/compliance/_search?pretty -d ' \
        { \
            \"query\": { \
                    \"bool\":{ \
                        \"must\":[{ \
                            \"term\" : { \"compliance_id.raw\" : \"Linux.0-0-a\" } \
                        },{ \
                            \"term\" : { \"namespace.raw\" : \"registry.ng.bluemix.net/icetest1/hello-test:latest\"} \
                        }] \
                    } \
            }, \
            \"filter\": { \
                \"bool\": { \
                    \"must\": [{ \
                        \"range\": { \
                            \"crawled_time\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }] \
                } \
            }, \
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["hits"]["total"]
        return outdata
    return -1


def GetComplianceTrueCount(dates_string):

    #cmd="curl --silent -k -XPOST 'http://"+elasticsearch_ip_port+"/compliance-"+dates_string+"/_count?pretty' -d ' \
    #    { \"query\": { \
    #            \"bool\": { \
    #                \"must\" :[{ \
    #                    \"term\" : { \"compliance_id.raw\" : \"Linux.0-0-a\" } \
    #                },{ \
    #                    \"term\" : { \"compliant.raw\" : \"true\" } \
    #                }] \
    #            } \
    #        } \
    #    }'"
    #p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    #ret = ""
    #for line in p.stdout.readlines():
    #    ret = ret+line
    #if ret != "":
    #    outdata = json.loads(ret)["count"]
    #    return outdata

    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-*/compliance/_search?pretty -d '{ \
            \"query\": { \
                \"bool\": { \
                    \"must\" :[{ \
                        \"term\" : { \"compliance_id.raw\" : \"Linux.0-0-a\" } \
                    },{ \
                        \"term\" : { \"compliant.raw\" : \"true\" } \
                    }] \
                } \
            }, \
            \"filter\": { \
                \"bool\": { \
                    \"must\": [{ \
                        \"range\": { \
                            \"crawled_time\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }] \
                } \
            }, \
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["hits"]["total"]
        return outdata
    return -1


def GetComplianceTrueCount_icetest1(dates_string):

    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-*/compliance/_search?pretty -d '{ \
            \"query\": { \
                \"bool\": { \
                    \"must\" :[{ \
                        \"term\" : { \"compliance_id.raw\" : \"Linux.0-0-a\" } \
                    },{ \
                        \"term\" : { \"compliant.raw\" : \"true\" } \
                    },{ \
                        \"term\" : { \"namespace.raw\" : \"registry.ng.bluemix.net/icetest1/hello-test:latest\"} \
                    }] \
                } \
            }, \
            \"filter\": { \
                \"bool\": { \
                    \"must\": [{ \
                        \"range\": { \
                            \"crawled_time\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }] \
                } \
            }, \
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["hits"]["total"]
        return outdata
    return -1


def GetComplianceFalseCount(dates_string):

    #cmd="curl --silent -k -XPOST 'http://"+elasticsearch_ip_port+"/compliance-"+dates_string+"/_count?pretty' -d ' \
    #    { \"query\": { \
    #            \"bool\": { \
    #                \"must\" :[{ \
    #                    \"term\" : { \"compliance_id.raw\" : \"Linux.0-0-a\" } \
    #                },{ \
    #                    \"term\" : { \"compliant.raw\" : \"false\" } \
    #                }] \
    #            } \
    #        } \
    #    }'"
    #p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    #ret = ""
    #for line in p.stdout.readlines():
    #    ret = ret+line
    #if ret != "":
    #    outdata = json.loads(ret)["count"]
    #    return outdata
    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-*/compliance/_search?pretty -d '{ \
            \"query\": { \
                \"bool\": { \
                    \"must\" :[{ \
                        \"term\" : { \"compliance_id.raw\" : \"Linux.0-0-a\" } \
                    },{ \
                        \"term\" : { \"compliant.raw\" : \"false\" } \
                    }] \
                } \
            }, \
            \"filter\": { \
                \"bool\": { \
                    \"must\": [{ \
                        \"range\": { \
                            \"crawled_time\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }] \
                } \
            }, \
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["hits"]["total"]
        return outdata
    return -1


def GetComplianceFalseCount_icetest1(dates_string):

    cmd="curl --silent -k -XPOST http://"+elasticsearch_ip_port+"/compliance-*/compliance/_search?pretty -d '{ \
            \"query\": { \
                \"bool\": { \
                    \"must\" :[{ \
                        \"term\" : { \"compliance_id.raw\" : \"Linux.0-0-a\" } \
                    },{ \
                        \"term\" : { \"compliant.raw\" : \"false\" } \
                    },{ \
                        \"term\" : { \"namespace.raw\" : \"registry.ng.bluemix.net/icetest1/hello-test:latest\"} \
                    }] \
                } \
            }, \
            \"filter\": { \
                \"bool\": { \
                    \"must\": [{ \
                        \"range\": { \
                            \"crawled_time\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }] \
                } \
            }, \
            \"size\":1 \
        }'"
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    if ret != "":
        outdata = json.loads(ret)["hits"]["total"]
        return outdata
    return -1


def GetSupportedOSCount(dates_string):

    cmd="curl --silent -k -XPOST 'http://"+elasticsearch_ip_port+"/vulnerabilityscan-*/vulnerabilityscan/_search?pretty' -d ' \
        { \
            \"query\": { \
                \"bool\": { \
                    \"must\" :[{ \
                        \"term\" : { \"description.raw\" : \"Overall vulnerability status\" } \
                    },{ \
                        \"term\" : { \"vulnerable_packages\" : -1 } \
                    }] \
                } \
            }, \
            \"filter\": { \
                \"bool\": { \
                    \"must\": [{ \
                        \"range\": { \
                            \"timestamp\" : { \
                                \"gt\" : \""+since_date+"\" \
                            } \
                        } \
                    }] \
                } \
            }, \
            \"size\":1 \
        }'"

    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ret = ""
    for line in p.stdout.readlines():
        ret = ret+line
    print ret
    if ret != "":
        outdata = json.loads(ret)["hits"]["total"]
        return outdata
    return -1


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

    parser = argparse.ArgumentParser(description="")
    parser.add_argument('--elasticsearch-url',  type=str, required=True, help='elasticsearch url: host:port')
    args = parser.parse_args()
    elasticsearch_ip_port = args.elasticsearch_url

    counter=0
    while True:

#        GetStatistic(counter)

        logline = ""
#        logline = logline + " " + str(GetImagePushCount())
#        logline = logline + " - " + str(GetComplianceTrueCountByRule())
#        logline = logline + "- " + str(GetComplianceFalseCountByRule())
#        logline = logline + "- " + str(GetVulnerableCount())
#        logline = logline + "- " + str(GetUniqueNamespaceCount())
#
#        #logline = logline + " -" + str(GetImageCrawlCount())
#        logline = logline + " -" + " 0"
#
#        logline = logline + " - " + str(GetOverallComplianceTrueCount())
#        logline = logline + str(GetOverallComplianceFalseCount())
#        logline = logline + " - " + str(GetVulnerablePackageDistribution())

        dstr="*"
        logline = logline + " " + str(GetImagePushCount(dstr) - GetImagePushCount_icetest1(dstr))
        logline = logline + " " + str(GetVulnerabilityScanStat(dstr) - GetVulnerabilityScanStat_icetest1(dstr))
        logline = logline + " " + str(GetVulnerabilityFalseCount(dstr) - GetVulnerabilityFalseCount_icetest1(dstr))
        logline = logline + " " + str(GetVulnerabilityTrueCount(dstr) - GetVulnerabilityTrueCount_icetest1(dstr))

        logline = logline + " " + str(GetComplianceScanStat(dstr) - GetComplianceScanStat_icetest1(dstr))
        logline = logline + " " + str(GetComplianceTrueCount(dstr) - GetComplianceTrueCount_icetest1(dstr))
        logline = logline + " " + str(GetComplianceFalseCount(dstr) - GetComplianceFalseCount_icetest1(dstr))

        #logline = logline + " - " + str(GetComplianceTrueCountByRule(dstr))
        logline = logline + " - " + str(GetComplianceTrueCountByRule_icetest1(dstr))
        #logline = logline + " - " + str(GetComplianceFalseCountByRule(dstr))
        logline = logline + " - " + str(GetComplianceFalseCountByRule_icetest1(dstr))
        logline = logline + " - " + str(GetSupportedOSCount(dstr))

        print logline
        logger.info("vastat "+version_code+" "+str(counter)+" "+str(datetime.datetime.now())+" "+logline)

        counter = counter + 1
        time.sleep(3600)
