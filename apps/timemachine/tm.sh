#!/bin/bash
ELASTIC_SERVICE=elastic2-cs.sl.cloud9.ibm.com:9200
SEARCH_SERVICE=cloudsight.sl.cloud9.ibm.com:8885

docker run -d -p 8600:8600 -e ELASTIC_SERVICE=$ELASTIC_SERVICE SEARCH_SERVICE=$SEARCH_SERVICE -e --name timemachine cloudsight/timemachine
