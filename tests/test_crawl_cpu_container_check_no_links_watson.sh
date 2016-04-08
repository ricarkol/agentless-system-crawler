#!/bin/bash

# Tests the --linkContainerLogFiles option for the OUTCONTAINER crawler mode 
# in watson environment.
# Expected behavior: crawler is stared without specifying --linkContainerLogFiles
# There should not be any container specific links in /var/log/crawl_container_logs/...
# Returns 1 if success, 0 otherwise

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# clean up temporaty files
rm -rf /var/log/crawler_container_logs/watson_test.service_1.service_v003.*

CONTAINER_NAME=test_crawl_cpu_container_check_no_links_watson

docker rm -f ${CONTAINER_NAME} 2> /dev/null > /dev/null
docker run -d --name $CONTAINER_NAME ubuntu bash -c "\
    echo CLOUD_APP_GROUP=\'watson_test\' >>/etc/csf_env.properties; \
    echo CLOUD_APP=\'service_1\' >>/etc/csf_env.properties; \
    echo CLOUD_TENANT=\'public\' >>/etc/csf_env.properties; \
    echo CLOUD_AUTO_SCALE_GROUP=\'service_v003\' >>/etc/csf_env.properties; \
    echo CRAWLER_METRIC_PREFIX=watson_test.service_1.service_v003  >>/etc/csf_env.properties; \
    sleep 600" 2> /dev/null > /dev/null

DOCKER_ID=`docker inspect -f '{{ .Id }}' ${CONTAINER_NAME}`
DOCKER_SHORT_ID=`echo $DOCKER_ID | cut -c 1-12`
NAMESPACE=watson_test.service_1.service_v003.${DOCKER_SHORT_ID}

python2.7 ../config_and_metrics_crawler/crawler.py --crawlmode OUTCONTAINER \
	--features=cpu --crawlContainers ${DOCKER_ID} \
	--environment watson > /dev/null

if [ -f /var/log/crawler_container_logs/${NAMESPACE} ]; then
	echo 0
else
	echo 1
fi

docker rm -f $CONTAINER_NAME > /dev/null
