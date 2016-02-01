#!/bin/bash

# Import environment variables containing the docker image names
. ../config/docker-images

if [ $# -eq 3 ] ; then
    REGISTRY="$1/"
    TAG="$2"
    CONTAINER_NAME="$3"
elif [ $# -eq 2 ] ; then
    TAG=$1
    CONTAINER_NAME="$2"
fi

if [ -z "$TAG" ] ; then
   TAG="latest"
fi

#install prereqs
apt-get update --fix-missing
apt-get install -y --fix-missing python-setuptools python-pip

# Map from image name to directory containing the corresponding Dockerfile
#docker build    --tag dev -t cloudsight/crawler                       collector/crawler
declare -A IMG_TO_DIR=(
  [$BASE_IMG]="../services/base"
  [$ES_IMG]="../services/elasticsearch"
  [$KAFKA_IMG]="../services/kafka"
  [$INDEXER_IMG]="../indexers/indexer"
  [$GENERIC_INDEXER_IMG]="../indexers/generic-indexer"
  [$NOTIFICATION_INDEXER_IMG]="../indexers/notification-indexer"
  [$SEARCH_IMG]="../apps/search"
  [$TIMEMACHINE_IMG]="../apps/timemachine"
  [$CONFIG_PARSER_IMG]="../apps/config_parser"
  [$VULNERABILITY_ANNOTATOR_IMG]="../apps/vulnerability_annotator"
  [$NOTIFICATION_PROCESSOR_IMG]="../apps/notification_processor"
  [$PASSWORD_ANNOTATOR_IMG]="../apps/password_annotator"
  [$COMPLIANCE_ANNOTATOR_IMG]="../apps/compliance_annotator"
  [$USN_CRAWLER_IMG]="../apps/usncrawler"
  [$REGISTRY_UPDATE_IMG]="../apps/registry_update"
  [$REGISTRY_MONITOR_IMG]="../apps/registry_monitor"
  [$VASTAT_REPORTER_IMG]="../apps/vastat_reporter"
  [$CONFIG_AND_METRICS_CRAWLER_IMG]="../collector/config_and_metrics_crawler"
  [$METRICS_SERVER_IMG]="../metrics_server"
)

# Get the kelk-base image if required - only useful for Jenkins builds
for img in ${KELK_BASE_DEPENDANT_IMAGES[@]}
do
  if [[ "$img" =~ "$CONTAINER_NAME" ]]; then
    echo docker pull "${REGISTRY}${BASE_IMG}:latest"
    docker pull "${REGISTRY}${BASE_IMG}:latest"
    echo docker tag "${REGISTRY}${BASE_IMG}:latest" ${BASE_IMG}
    docker tag "${REGISTRY}${BASE_IMG}:latest" ${BASE_IMG}
  fi
done

matched=false
for i in ${!IMG_TO_DIR[@]}
do
  if [[ "$i" =~ "$CONTAINER_NAME" ]]; then
     matched=true
     echo "Building docker image: ${REGISTRY}$i:$TAG"
     echo "  - directory: ${IMG_TO_DIR[$i]}"
     (cd ${IMG_TO_DIR[$i]} && docker build -t "${REGISTRY}$i:$TAG" .)

     if [ "$i" = "$BASE_IMG" ] ; then
         # This is only useful when building locally
         echo "============>" docker tag "${REGISTRY}${BASE_IMG}:$TAG" ${BASE_IMG}
         docker tag "${REGISTRY}${BASE_IMG}:$TAG" ${BASE_IMG}
     fi
  fi
done

if [[ $matched =~ false ]]; then
   echo -n "Failed to build $CONTAINER_NAME as it is not one of: "
   echo "${!IMG_TO_DIR[@]}"  | sed 's/cloudsight\///g'
fi
