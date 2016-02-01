#!/bin/bash


#
# (c) IBM Research 2015
#

# Import environment variables containing the docker image names
. ../config/docker-images


if [ $# -lt 2 ] || [ $# -gt 5 ]
    then
    echo "Usage: $0 <target_registry> <tag> container_name [<build_registry> [latest]] "
    exit 1
fi


REGISTRY=$1
TAG=$2
CONTAINER_NAME=$3
BUILD_REGISTRY=$4
LATEST=$5

matched=false
for img in ${DEPLOYMENT_IMAGES[@]}
do
  if [[ "$img" =~ "$CONTAINER_NAME" ]]; then
     matched=true
     if [ -n "$BUILD_REGISTRY" ]
         then
         echo "Pulling image ${BUILD_REGISTRY}/$img/$TAG"
         docker pull "${BUILD_REGISTRY}/$img:$TAG"
         docker tag -f "${BUILD_REGISTRY}/$img:$TAG" "${REGISTRY}/$img:$TAG"
     fi
     echo "Pushing docker image: ${REGISTRY}/$img:$TAG"
     docker push "${REGISTRY}/${img}:${TAG}"
     if [ -n "$LATEST" ]
      then
         docker tag -f "${REGISTRY}/$img:$TAG" "${REGISTRY}/$img:latest"
         docker push "${REGISTRY}/${img}:latest"
    fi
  fi
done

if [[ $matched =~ false ]]; then
    if [[ "$BASE_IMG" =~ "$CONTAINER_NAME" ]]; then
       echo "Pushing base image: ${REGISTRY}/${BASE_IMG}:latest"
       docker push "${REGISTRY}/${BASE_IMG}:latest"
   else
       echo -n "Failed to push $CONTAINER_NAME as it is not one of: "
       echo "${DEPLOYMENT_IMAGES[@]}"  | sed 's/cloudsight\///g'
   fi
fi
