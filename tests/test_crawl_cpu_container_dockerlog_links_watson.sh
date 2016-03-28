#!/bin/bash

# Tests the --linkContainerLogFiles option for the OUTCONTAINERcrawler mode .
# Expected behavior: crawler is stared with --linkContainerLogFiles
# Following should be true:
#   1. There should be a container specific dir in /var/log/crawl_container_logs/
#   2. There should be log files specified in defaults.py 
#      for watson: these are: 
#               /etc/csf_env.properties
#               /var/log/messages  
#               docker.log
#   3. all the files listed in /etc/logfiles in docker container
#      the file /etc/logfiles is optional, can be empty
#
# Returns 1 if success, 0 otherwise

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# clean up temporay files
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
logdir=/var/log/crawler_container_logs/$NAMESPACE

python2.7 ../config_and_metrics_crawler/crawler.py --crawlmode OUTCONTAINER \
	--features=cpu --crawlContainers ${DOCKER_ID} \
     --linkContainerLogFiles \
	--environment watson > /dev/null

if [ ! -d $logdir ]; then
    echo 0      # expected container logdir did not exist
    exit 
fi

if [ ! -f $logdir/etc/csf_env.properties ] ; then
    echo 0      # file configured in defaults.py dir not exist
    exit 
fi

if [ ! -h $logdir/var/log/messages ]; then
    echo 0      # file configured in defaults.py dir not exist
    exit 
fi

if [ ! -f $logdir/docker.log ] ; then
    echo 0      # file configured in defaults.py dir not exist
    exit 
fi

echo 1
docker rm -f $CONTAINER_NAME > /dev/null
