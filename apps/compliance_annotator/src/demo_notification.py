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

from datetime import datetime

def ParseIndividualNamespace(filename):

    timeline = {}
    image_name = ""
    container_id = ""
    plot_data = {}
    events = []

    with open(filename, "r") as fp:
        for line in fp:
            if not ('processor') in line:
                continue

            data_json = {}
            try:
                data_json = json.loads(line)
            except Exception as err:
                print err 
                print filename
                print line
                pass

            if (data_json == {}):
                continue

            namespace = data_json["namespace"]
            tmp = namespace.split("/")
            image_name = tmp[0]
            container_id = tmp[1]
            processor = data_json["processor"]
            status = data_json["status"]

            #define the 1st layer of the map
            try:
                timeline[processor]
            except KeyError:
                timeline[processor] = {}

            try:
                timeline[processor][status]
            except KeyError:
                #if the raw data doesn't contain timestamp_ms
                try:
                    data_json["timestamp_ms"]
                except KeyError:
                    ts = data_json["timestamp"]
                    ts = ts.replace("-", "/")
                    ts = ts.replace("T", " ")
                    ts_main = ts[0:-7]
                    ts_ms = ts[-6:]

                    epoch = int(time.mktime(time.strptime(ts_main, '%Y/%m/%d %H:%M:%S')))
                    epoch = epoch * 1000 + int(int(ts_ms) / 1000)
                    data_json["timestamp_ms"] = epoch

                timeline[processor][status] = data_json["timestamp_ms"]
                having_pair = False
                if (status == "completed"):
                    try:
                        timeline[processor]["start"]
                        having_pair = True
                    except Exception as err:
#                        print err
                        pass
                else:
                    try:
                        timeline[processor]["completed"]
                        having_pair = True
                    except Exception as err:
#                        print err
                        pass

                if (having_pair):
                    duration = int(timeline[processor]["completed"]) - int(timeline[processor]["start"])
                    timeline[processor]["duration"] = duration
                        
                    times = []
                    times.append({"starting_time":timeline[processor]["start"], "ending_time":timeline[processor]["completed"]})
                    events.append({"label": processor, "times": times})



    namespace = image_name + "." + container_id
    plot_data["name"] = namespace
    plot_data["events"] = events
    #print json.dumps(plot_data, indent = 2)

#write current namespace for status report to pickup and generate status html page
    #fp = open("timeline/namespace.progress", "a")
    #fp.write(namespace+"\n")
    #fp.close()

#data file status report page will process to generate html page
    filename = "timeline/" + namespace + ".json"
    fp = open(filename, "w")
    fp.write(json.dumps(plot_data))
    fp.close()

    return timeline

if __name__ == '__main__':

    html = open("events.html", "w")
    head = "<html>\n<head>\n"
    head = head + "<style type='text/css'>\n"
    head = head + ".myTable { background-color:#FFFFFF;border-collapse:collapse; }\n"
    head = head + ".myTable th { background-color:#6B7De7;color:white; font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 12px; }\n"
    head = head + ".myTable td,\n"
    head = head + ".myTable th { padding:5px;border:1px solid #111111; font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 13px; }\n"
    head = head + "</style>\n"
    head = head + "<body>\n"
    head = head + "<table class=myTable>\n"
    head = head + "<tr><th><b>Image Name</b></th>"
    head = head + "<th><b>Container ID</b></th>"
    head = head + "<th><b>Crawl Time (UTC)</b></th>"
    head = head + "<th><b>Crawl Duration (ms)</b></th>"
    head = head + "<th><b>Vulnerability Duration (ms)</b></th>"
    head = head + "<th><b>Compliance Duration (ms)</b></th>"
    head = head + "<th><b>Indexer Duration (ms)</b></th>"
    head = head + "</tr>"
    html.write(head)

    namespace_progress = "timeline/namespace.progress"
            
    with open(namespace_progress, "r") as np:
        for line in np:
            timeline = ParseIndividualNamespace("timeline/" + line.rstrip('\n'))

            tmp = line.rstrip('\n').split(".")
            image_name = tmp[0]
            container_id = tmp[1]

            body = "<tr><td>" + image_name + "</td>\n"
            body =  body + "<td>" + container_id + "</td>\n"
            value = ""
            inprogress = False
            try:
                epoch = time.gmtime(timeline["crawler"]["start"]/1000)
                value = time.strftime("%Y/%m/%d %H:%M:%S", epoch)
            except:
                value = ""
                pass
            body =  body + "<td>" + value + "</td>\n"

            events = ["crawler", "vulnerability_annotator-0", "compliance_annotator", "config_indexer_0"]
            for event in events:
                start = ""
                end = ""

                try:
                    value = str(timeline[event]["duration"])
                    epoch = time.gmtime(timeline[event]["start"]/1000)
                    start = time.strftime("%Y/%m/%d %H:%M:%S", epoch)
                    epoch = time.gmtime(timeline[event]["completed"]/1000)
                    end = time.strftime("%Y/%m/%d %H:%M:%S", epoch)
           
                except:
                    value = ""
                    pass
                body = body + "<td title=\"" + start + " to " + end + "\">" + value + "</td>\n"

            body = body + "</tr>\n"
            html.write(body)
            #print timeline

    html.write("</table>\n</body>\n</html>\n")
    html.close()
