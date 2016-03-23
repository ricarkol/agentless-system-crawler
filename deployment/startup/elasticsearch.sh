#!/bin/bash

#CONFIG_FILE=setup_env.sh

USAGE="Usage $0 start|stop|delete [1-5] [<publish-host>]"

if [ $# -lt 2 ] || [ $# -gt 3 ] ; then
    echo $USAGE
    exit 1
fi

#re='^[1-2]$'
#if ! [[ $2 =~ $re ]] ; then
#   echo "error: elasticsearch instance number must be in [1-2] " >&2; exit 1
#fi

if ! [ -f "$CONFIG_FILE" ] ; then
    echo "Cannot open configuration file $CONFIG_FILE"
    exit 1
fi

. $CONFIG_FILE

PROC_ID=$2
CONTAINER_NAME=${ES_CONT}_${PROC_ID}
PUBLISH_HOST=$3

if [ -z "$IMAGE_TAG" ] ; then
    IMAGE_TAG="latest"
fi

if [ -z "$PUBLISH_HOST" ] ; then
    PUBLISH_HOST=`hostname --fqdn`
fi

HOSTNAME=`hostname` 

# Make sure the volumes to be mounted by the containers exist on the host
mkdir -p $ES_DATA_VOLUME
mkdir -p $ES_LOGS_VOLUME

HOST_SUPERVISOR_LOG_DIR=${HOST_CONTAINER_LOG_DIR}/${CONTAINER_NAME}/${SUPERVISOR_DIR}
mkdir -p HOST_SUPERVISOR_LOG_DIR

case $1 in
    start)
        echo "Starting ${CONTAINER_NAME}."
        if [ ! -z "$REGISTRY" ]; then
            set -x
            docker pull $REGISTRY/$ES_IMG:$IMAGE_TAG 2>&1 > /dev/null
            docker tag -f $REGISTRY/$ES_IMG:$IMAGE_TAG $ES_IMG
            set +x
        fi
        # Start Elasticsearch
        set -x
        docker run -d --restart=always \
              -p $ES_PORT:$ES_PORT -p 9300:9300 -p 9400:9400 -p 8888:80 -h $HOSTNAME \
              -e ES_HEAP_SIZE=$ES_HEAP_SIZE -e ES_CLUSTER_NAME=$ES_CLUSTER_NAME \
              -e ES_NODE_NAME=$HOSTNAME -e ES_PUBLISH_HOST=$PUBLISH_HOST \
              -e ES_UNICAST_HOSTS=$ES_UNICAST_HOSTS \
              -v $ES_DATA_VOLUME:/opt/elasticsearch/data -v $ES_LOGS_VOLUME:/opt/elasticsearch/logs \
              -v $HOST_SUPERVISOR_LOG_DIR:$CONTAINER_SUPERVISOR_LOG_DIR \
              --name $CONTAINER_NAME $ES_IMG

        STAT=$?
        set +x
        exit $STAT
        ;;

   stop)
        echo -n "Stopping container: "
        docker stop ${CONTAINER_NAME}
        ;;
   delete)
        echo -n "Removing container: "
        docker rm ${CONTAINER_NAME}
        ;;
   *)
        echo $USAGE
        exit 1
        ;;
esac
