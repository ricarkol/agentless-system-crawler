#!/bin/bash

# Tests the OUTCONTAINER crawler mode for watson environment
# Returns 1 if success, 0 otherwise

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

HOST_NAMESPACE=dev-test
CONTAINER_NAME=test_crawl_cpu_container_check_metadata_watson
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

python2.7 ../config_and_metrics_crawler/crawler.py --crawlmode OUTCONTAINER \
	--features=cpu --crawlContainers $DOCKER_ID \
	--environment watson --numprocesses 1 --namespace ${HOST_NAMESPACE} > /tmp/check_metadata_frame

docker rm -f ${CONTAINER_NAME} > /dev/null

#{
#  "since_timestamp": 1445848019,
#  "container_long_id": "ec120e72846942d3f0805a5facf17d24982dd54c9ebb78367cc0b9ff0dfb9019",
#  "features": "cpu",
#  "timestamp": "2015-12-11T09:51:37-0600",
#  "since": "BOOT",
#  "compress": false,
#  "system_type": "container",
#  "container_name": "test_crawl_cpu_container_1",
#  "container_image": "ca4d7b1b9a51f72ff4da652d96943f657b4898889924ac3dae5df958dba0dc4a",
#  "namespace": "10.91.71.246/test_crawl_cpu_container_1"
#}

TIMESTAMP_DAY_PART=`date +"%Y-%m-%dT"`
NAMESPACE=${HOST_NAMESPACE}.watson_test.service_1.service_v003.${DOCKER_SHORT_ID}

grep ^metadata /tmp/check_metadata_frame \
			| grep '"system_type":"container"' \
			| grep '"features":"cpu"' \
			| grep '"timestamp":"'${TIMESTAMP_DAY_PART} \
			| grep '"container_name":"'${CONTAINER_NAME}'"' \
			| grep '"container_image":"'${CONTAINER_IMAGE}'"' \
			| grep '"namespace":"'${NAMESPACE}'"' \
			| grep -c metadata

rm -rf /var/log/crawler_container_logs/${HOST_NAMESPACE}.*
