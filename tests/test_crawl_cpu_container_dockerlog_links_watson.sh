#!/bin/bash

# Tests the --linkContainerLogFiles option for the OUTCONTAINERcrawler mode .
# Expected behavior: crawler is stared specifying --linkContainerLogFiles
# Following should be true:
#   1. There should container specific links in /var/log/crawl_container_logs/...
# Returns 1 if success, 0 otherwise

# Tests the --linkContainerLogFiles option for the OUTCONTAINERcrawler mode .
# This option maintains symlinks for some logfiles inside the container. By
# default /var/log/messages and the docker (for all containers) are symlinked
# to a central location: /var/log/crawl_container_logs/...
# Returns 1 if success, 0 otherwise

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# clean up temporaty files
rm -rf /var/log/crawler_container_logs/watson_test.service_1.service_v003.*

CONTAINER_NAME=test_crawl_cpu_container_log_links_1
CONTAINER_IMAGE=`docker inspect --format {{.Id}} ubuntu:latest`

docker rm -f ${CONTAINER_NAME} 2> /dev/null > /dev/null
docker run -d --name $CONTAINER_NAME ubuntu bash -c "\
    echo CLOUD_APP_GROUP=\'watson_test\' >>/etc/csf_env.properties; \
    echo CLOUD_APP=\'service_1\' >>/etc/csf_env.properties; \
    echo CLOUD_TENANT=\'public\' >>/etc/csf_env.properties; \
    echo CLOUD_AUTO_SCALE_GROUP=\'service_v003\' >>/etc/csf_env.properties; \
    echo CRAWLER_METRIC_PREFIX=#CLOUD_APP_GROUP:#CLOUD_APP:#CLOUD_AUTO_SCALE_GROUP | sed 's/#/\$/g'  >>/etc/csf_env.properties; \
    sleep 600" 2> /dev/null > /dev/null

DOCKER_ID=`docker inspect -f '{{ .Id }}' ${CONTAINER_NAME}`
DOCKER_SHORT_ID=`echo $DOCKER_ID | cut -c 1-12`
NAMESPACE=watson_test.service_1.service_v003.${DOCKER_SHORT_ID}

python2.7 ../config_and_metrics_crawler/crawler.py --crawlmode OUTCONTAINER \
	--features=cpu --crawlContainers ${DOCKER_ID} \
     --linkContainerLogFiles \
	--environment watson > /dev/null

grep -c $MSG /var/log/crawler_container_logs/f75ec4e7-eb9d-463a-a90f-f8226572fbcc/0000/${CONTAINER_ID}/docker.log

docker rm -f $NAME > /dev/null
