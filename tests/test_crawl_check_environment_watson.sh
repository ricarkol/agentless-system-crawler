#!/bin/bash

# Tests the watson environment.  2 containers are created, one ready for
# watson, and one not. Check that only the watson one is crawled.  
# Returns 1 if success, 0 otherwise

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

HOST_NAMESPACE=dev-test
CONTAINER_NAME_1=test_crawl_check_environment_watson_1
CONTAINER_NAME_2=test_crawl_check_environment_watson_2
CONTAINER_IMAGE=`docker inspect --format {{.Id}} ubuntu:latest`

# start container 1 (watson)
docker rm -f ${CONTAINER_NAME_1} 2> /dev/null > /dev/null
docker run -d --name $CONTAINER_NAME_1 ubuntu bash -c "\
    echo CLOUD_APP_GROUP=\'watson_test\' >>/etc/csf_env.properties; \
    echo CLOUD_APP=\'service_1\' >>/etc/csf_env.properties; \
    echo CLOUD_TENANT=\'public\' >>/etc/csf_env.properties; \
    echo CLOUD_AUTO_SCALE_GROUP=\'service_v003\' >>/etc/csf_env.properties; \
    echo CRAWLER_METRIC_PREFIX=watson_test.service_1.service_v003  >>/etc/csf_env.properties; \
    sleep 600" 2> /dev/null > /dev/null

DOCKER_ID_1=`docker inspect -f '{{ .Id }}' ${CONTAINER_NAME_1}`
DOCKER_SHORT_ID1=`echo $DOCKER_ID_1 | cut -c 1-12`

# start container 2 (not-watson)
docker rm -f ${CONTAINER_NAME_2} 2> /dev/null > /dev/null
docker run -d --name ${CONTAINER_NAME_2} ${CONTAINER_IMAGE} sleep 60 2> /dev/null > /dev/null
DOCKER_ID_2=`docker inspect -f '{{ .Id }}' ${CONTAINER_NAME_2}`
DOCKER_SHORT_ID2=`echo $DOCKER_ID_2 | cut -c 1-12`

python2.7 ../config_and_metrics_crawler/crawler.py --crawlmode OUTCONTAINER \
	--features=cpu --crawlContainers $DOCKER_ID_1,$DOCKER_ID_2 \
	--environment watson --namespace ${HOST_NAMESPACE}  > /tmp/check_metadata_frame

NAMESPACE_1=${HOST_NAMESPACE}.watson_test.service_1.service_v003.$DOCKER_SHORT_ID1
NAMESPACE_2=${HOST_NAMESPACE}.watson_test.service_1.service_v003.$DOCKER_SHORT_ID2

N1=`grep -c cpu-0 /tmp/check_metadata_frame`
N2=`grep -c ^metadata /tmp/check_metadata_frame`
N3=`grep -c '"namespace":"'${NAMESPACE_1}'"' /tmp/check_metadata_frame`
N4=`grep -c '"namespace":"'${NAMESPACE_2}'"' /tmp/check_metadata_frame`

docker rm -f ${CONTAINER_NAME_1} > /dev/null
docker rm -f ${CONTAINER_NAME_2} > /dev/null

# Container 1 should be crawled, and its namespace should be in watson format: N1=1, N2=1, N3=1
# Container 2 should not be crawled: N4=0
if [ $N1 == "1" ] && [ $N2 == "1" ] && [ $N3 == "1" ] && [ $N4 == "0" ]
then
	echo 1
else
	echo 0
fi

rm -rf /var/log/crawler_container_logs/${HOST_NAMESPACE}.*