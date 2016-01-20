#!/bin/bash


#
# (c) IBM Research 2015
#

if [ $# -eq 3 ] ; then
	CONTAINER_NAME=
elif [ $# -eq 4 ] ; then
	CONTAINER_NAME=$4
else
	echo "Usage: $0 <env> <tag> <source_registry> [<container>]"
	exit 1
fi

ENV=$1
TAG=$2
SOURCE_REGISTRY=$3

. ../config/hosts.${ENV}
# Import environment variables containing the docker image names
. ../config/docker-images

if [ -z "$CONTAINER_NAME" ]
	then
	./push-images-to-registry.sh $DEPLOYMENT_REGISTRY $TAG $SOURCE_REGISTRY 
	for img in ${DEPLOYMENT_IMAGES[@]}
	do
		echo "Tagging ${DEPLOYMENT_REGISTRY}/$img:$TAG as latest"
		docker tag -f "${DEPLOYMENT_REGISTRY}/$img:$TAG" "${DEPLOYMENT_REGISTRY}/$img:latest"
	done

else
	./push-an-image-to-registry.sh $DEPLOYMENT_REGISTRY $TAG $CONTAINER_NAME $SOURCE_REGISTRY 
	echo "Tagging ${DEPLOYMENT_REGISTRY}/$CONTAINER_NAME:$TAG as latest"
	docker tag -f "${DEPLOYMENT_REGISTRY}/$CONTAINER_NAME:$TAG" "${DEPLOYMENT_REGISTRY}/$CONTAINER_NAME:latest"
fi
