#!/bin/bash


#
# (c) IBM Research 2015
#

if [ $# -ne 3 ]
    then
    echo "Usage: $0 <env> <tag> <source_registry>"
    exit 1
fi

ENV=$1
TAG=$2
SOURCE_REGISTRY=$3

. ../config/hosts.${ENV}

./push-images-to-registry.sh $DEPLOYMENT_REGISTRY $TAG $SOURCE_REGISTRY 
