#!/bin/bash

# Tests the watson environment.  The env properties file exists 
# but does not contain required CRAWLER_METRIC_PREFIX
# Returns 1 if success, 0 otherwise

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

CONTAINER_NAME_1=test_crawl_bad_properties_watson_1

#    echo CRAWLER_METRIC_PREFIX=#CLOUD_APP_GROUP:#CLOUD_APP:#CLOUD_AUTO_SCALE_GROUP | sed 's/#/\$/g'  >>/etc/csf_env.properties; \
# start container 1 (watson)
docker rm -f ${CONTAINER_NAME_1} 2> /dev/null > /dev/null
docker run -d --name $CONTAINER_NAME_1 ubuntu bash -c "\
    echo CLOUD_APP_GROUP=\'watson_test\' >>/etc/csf_env.properties; \
    echo CLOUD_APP=\'service_1\' >>/etc/csf_env.properties; \
    echo CLOUD_TENANT=\'public\' >>/etc/csf_env.properties; \
    echo CLOUD_AUTO_SCALE_GROUP=\'service_v003\' >>/etc/csf_env.properties; \
    echo CRAWLER_METRIC_PREFIX=CLOUD_APP_GROUP:#CLOUD_APP:#CLOUD_AUTO_SCALE_GROUP | sed 's/#/\$/g'  >>/etc/csf_env.properties; \
    sleep 600" 2> /dev/null > /dev/null

DOCKER_ID_1=`docker inspect -f '{{ .Id }}' ${CONTAINER_NAME_1}`
DOCKER_SHORT_ID1=`echo $DOCKER_ID_1 | cut -c 1-12`

python2.7 ../config_and_metrics_crawler/crawler.py --crawlmode OUTCONTAINER \
	--features=cpu --crawlContainers $DOCKER_ID_1,$DOCKER_ID_2 \
	--environment watson > /tmp/check_metadata_frame

NAMESPACE_1=watson_test.service_1.service_v003.$DOCKER_SHORT_ID1

N1=`grep -c cpu-0 /tmp/check_metadata_frame`
N2=`grep -c ^metadata /tmp/check_metadata_frame`
N3=`grep -c '"namespace":"'${NAMESPACE_1}'"' /tmp/check_metadata_frame`

docker rm -f ${CONTAINER_NAME_1} > /dev/null

if [ $N1 == "0" ] && [ $N2 == "0" ]  && [ $N3 == "0" ]
then
	echo 1
else
	echo 0
fi
