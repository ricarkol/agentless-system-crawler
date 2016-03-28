#!/bin/bash

# Tests the links created for file specifid in /etc/logfiles 
# crawler command-line options: --crawlermode OUTCONTAINER --features cpu  
#          --linkContainerLogFiles --environment watson 
#
# The test container has two files listed in /etc/logfiles
# /var/log/test1 (exists at the time of crawling)
# /var/log/test2 (does not exist the time of crawling)
#
# Expected behavior: 
#   1. /var/log/crawl_container_logs/<container_name>.<container_shortid>/var/log/test1
#      exists
#
#   2. /var/log/crawl_container_logs/<container_name>.<container_shortid>/var/log/test2
#      if only a symbolic link at the time of checking
#
#   3. /var/log/crawl_container_logs/<container_name>.<container_shortid>/var/log/test2
#      is a file after 20 secs
#
# Returns 1 if success, 0 otherwise

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# clean up temporay files
rm -rf /var/log/crawler_container_logs/watson_test.service_1.service_v003.*

CONTAINER_NAME=test_crawl_cpu_container_log_links_1

docker rm -f ${CONTAINER_NAME} 2> /dev/null > /dev/null
docker run -d --name $CONTAINER_NAME ubuntu bash -c "\
    echo CLOUD_APP_GROUP=\'watson_test\' >>/etc/csf_env.properties; \
    echo CLOUD_APP=\'service_1\' >>/etc/csf_env.properties; \
    echo CLOUD_TENANT=\'public\' >>/etc/csf_env.properties; \
    echo CLOUD_AUTO_SCALE_GROUP=\'service_v003\' >>/etc/csf_env.properties; \
    echo CRAWLER_METRIC_PREFIX=#CLOUD_APP_GROUP:#CLOUD_APP:#CLOUD_AUTO_SCALE_GROUP | sed 's/#/\$/g'  >>/etc/csf_env.properties; \
    echo /var/log/test1.log >> /etc/logfiles; \
    echo /var/log/test2.log >> /etc/logfiles; \
    echo $CONTAINER_NAME >> /var/log/test1.log; \
    sleep 5; \
    echo $CONTAINER_NAME >> /var/log/test2.log; \
    sleep 600" 2> /dev/null > /dev/null

DOCKER_ID=`docker inspect -f '{{ .Id }}' ${CONTAINER_NAME}`
DOCKER_SHORT_ID=`echo $DOCKER_ID | cut -c 1-12`
NAMESPACE=watson_test.service_1.service_v003.${DOCKER_SHORT_ID}
logdir=/var/log/crawler_container_logs/$NAMESPACE

python2.7 ../config_and_metrics_crawler/crawler.py --crawlmode OUTCONTAINER \
	--features=cpu --crawlContainers ${DOCKER_ID} \
     --linkContainerLogFiles \
	--environment watson > /dev/null

if [ ! -f $logdir/var/log/test1.log ]; then
    echo 0      # expected log file did not exist
    exit 
fi

if [ ! -h $logdir/var/log/test2.log ]; then
    echo 0      # expected link did not exist
    exit 
fi

sleep 5 # wait for the 
if [ ! -f $logdir/var/log/test2.log ]; then
    echo 0      # expected log file did not exist
    exit 
fi

if [ "1" != `grep -c $CONTAINER_NAME $logdir/var/log/test2.log` ]; then
    echo 0     # the log file did not contain expected content
fi

echo 1
docker rm -f $CONTAINER_NAME > /dev/null
