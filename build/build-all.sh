#!/bin/bash

# Import environment variables containing the docker image names
. ../config/docker-images

if [ $# -eq 2 ] ; then
    REGISTRY="$1/"
    TAG="$2"
elif [ $# -eq 1 ] ; then
    TAG=$1
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
)

docker pull ubuntu:trusty 
docker pull ubuntu:14.04

# Builds the search service Python package
(cd ../apps/search && ./build.sh)
if [ $? -ne 0 ]; then
  echo ""
  echo "Failed to build search service!"
  echo ""
  exit 2
fi

# Builds all docker images
for i in ${!IMG_TO_DIR[@]}
do
  echo "Building docker image: ${REGISTRY}$i:$TAG"
  echo "  - directory: ${IMG_TO_DIR[$i]}"
  (cd ${IMG_TO_DIR[$i]} && docker build -t "${REGISTRY}$i:$TAG" .)

  if [ "$i" = "$BASE_IMG" ] ; then
      docker tag "${REGISTRY}${BASE_IMG}:$TAG" ${BASE_IMG}
  fi
done

