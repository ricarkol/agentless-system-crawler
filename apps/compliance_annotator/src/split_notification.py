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

import os.path
timeline = {}
image_name = ""
container_id = ""
plot_data = {}
events = []

if __name__ == '__main__':

    with open("event.dat", "r") as fp:
        for line in fp:
            if not ('processor') in line:
                continue

            if ('"crawler"') in line:
                line = line.replace(',"timestamp_ms"', '","timestamp_ms"', 1)
                line = line.replace('"timestamp":', '"timestamp":"', 1)

            data_json = json.loads(line)
            
            namespace = data_json["namespace"]
            tmp = namespace.split("/")
            image_name = tmp[0]
            container_id = tmp[1]

            namespace = image_name + "." + container_id
            fp = open("timeline/" + namespace, "a")
            fp.write(line)
            fp.close()

            file_path = "timeline/namespace.progress"
            if os.path.exists(file_path):

                with open (file_path, "r") as myfile:
                    data=myfile.read()

                if not (namespace) in data:
                    fp = open(file_path, "a")
                    fp.write(namespace+"\n")
                    fp.close()
            else:
                fp = open(file_path, "a")
                fp.write(namespace+"\n")
                fp.close()


