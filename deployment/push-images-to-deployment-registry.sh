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

if [ -z "$CONTAINER_NAME" ]
	then
	./push-images-to-registry.sh $DEPLOYMENT_REGISTRY $TAG $SOURCE_REGISTRY latest
else
	./push-an-image-to-registry.sh $DEPLOYMENT_REGISTRY $TAG $CONTAINER_NAME $SOURCE_REGISTRY latest
fi
