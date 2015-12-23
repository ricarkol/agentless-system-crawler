#!/bin/bash

TIMEMACHINE_PORT=8600
ELASTIC_SERVICE=elastic2-cs.sl.cloud9.ibm.com:9200
SEARCH_SERVICE=cloudsight.sl.cloud9.ibm.com:8885
#ELASTIC_SERVICE=demo3.sl.cloud9.ibm.com:9200
#SEARCH_SERVICE=demo3.sl.cloud9.ibm.com:8885

./timemachine -v --search-service $SEARCH_SERVICE --elastic-search-cluster $ELASTIC_SERVICE --port $TIMEMACHINE_PORT
