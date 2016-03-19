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
  [$REGISTRY_UPDATE_IMG]="../apps/registry_update_java"
  [$REGISTRY_MONITOR_IMG]="../apps/registry_monitor"
  [$VASTAT_REPORTER_IMG]="../apps/vastat_reporter"
  [$CONFIG_AND_METRICS_CRAWLER_IMG]="../collector/config_and_metrics_crawler"
  [$METRICS_SERVER_IMG]="../metrics-server"
  [$UPTIME_SERVER_IMG]="../uptime-server"
  [$IMAGE_RESCANNER_IMG]="../apps/image_rescanner"
  [$MT_LOGSTASH_FORWARDER_IMG]="../mt-logstash-forwarder"
)

# Get the kelk-base image if required - only useful for Jenkins builds
for img in ${KELK_BASE_DEPENDENT_IMAGES[@]}
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

     if [[ "${IMG_TO_DIR[$i]}" =~ "_java" ]] ; then
         echo "Building Java image from ${IMG_TO_DIR[$i]}"
         (cd ${IMG_TO_DIR[$i]} && /opt/Ant1.8.2/bin/ant )
     fi

     echo "Building docker image: ${REGISTRY}$i:$TAG"
     echo "  - directory: ${IMG_TO_DIR[$i]}"
     (cd ${IMG_TO_DIR[$i]} && docker build -t "${REGISTRY}$i:$TAG" .)

        build_STAT=$?
          if [ $build_STAT -ne 0 ]
              then
              echo "Build Failed"
              exit $build_STAT
          fi

     if [ "$i" = "$BASE_IMG" ] ; then
         # This is only useful when building locally
         echo "docker tag ${REGISTRY}${BASE_IMG}:$TAG" ${BASE_IMG}
         docker tag "${REGISTRY}${BASE_IMG}:$TAG" ${BASE_IMG}

            tag_STAT=$?
              if [ $tag_STAT -ne 0 ]
                  then
                  echo "Build Failed"
                  exit $tag_STAT
              fi
     fi
  fi
done

if [[ $matched =~ false ]]; then
   echo -n "Failed to build $CONTAINER_NAME as it is not one of: "
   echo "${!IMG_TO_DIR[@]}"  | sed 's/cloudsight\///g'
   exit 1
fi
