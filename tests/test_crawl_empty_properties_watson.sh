#!/bin/bash

# Tests the OUTCONTAINER crawler mode for watson environment
# The one of the properties in /etc/csf_env.properties file
# is uninitialized. Should result in skipping the container
# Returns 1 if success, 0 otherwise

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

CONTAINER_NAME=test_crawl_export_in_properties_watson
CONTAINER_IMAGE=`docker inspect --format {{.Id}} ubuntu:latest`

docker rm -f ${CONTAINER_NAME} 2> /dev/null > /dev/null
docker run -d --name $CONTAINER_NAME ubuntu bash -c "\
    echo CLOUD_APP_GROUP='watson_test' >>/etc/csf_env.properties; \
    echo CLOUD_APP= >>/etc/csf_env.properties; \
    echo CLOUD_TENANT=\'public\' >>/etc/csf_env.properties; \
    echo CLOUD_AUTO_SCALE_GROUP=\'service_v003\' >>/etc/csf_env.properties; \
    echo CRAWLER_METRIC_PREFIX=#CLOUD_APP_GROUP:#CLOUD_APP:#CLOUD_AUTO_SCALE_GROUP | sed 's/#/\$/g'  >>/etc/csf_env.properties; \
    sleep 600" 2> /dev/null > /dev/null

DOCKER_ID=`docker inspect -f '{{ .Id }}' ${CONTAINER_NAME}`
DOCKER_SHORT_ID=`echo $DOCKER_ID | cut -c 1-12`

python2.7 ../config_and_metrics_crawler/crawler.py --crawlmode OUTCONTAINER \
	--features=cpu --crawlContainers $DOCKER_ID \
	--environment watson --numprocesses 1 > /tmp/check_metadata_frame

docker rm -f ${CONTAINER_NAME} > /dev/null

file_size=`wc -c /tmp/check_metadata_frame | awk '{print $1}' `
if [ $file_size == "0" ] ; then
    echo 1
else
    echo 0
fi
