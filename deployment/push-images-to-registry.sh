#!/bin/bash


#
# (c) IBM Research 2015
#

# Import environment variables containing the docker image names
. ../config/docker-images


if [ $# -lt 2 ] || [ $# -gt 4 ]
    then
    echo "Usage: $0 <target_registry> <tag> [<build_registry> [latest]]"
    exit 1
fi


REGISTRY=$1
TAG=$2
BUILD_REGISTRY=$3
LATEST=$4

for img in ${DEPLOYMENT_IMAGES[@]}
do
  if [ "$i" != "$BASE_IMG" ]
      then
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
