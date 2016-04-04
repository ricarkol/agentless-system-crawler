#!/bin/bash

#CONFIG_FILE=setup_env.sh

USAGE="Usage $0 start|stop|delete container_number"

if [ $# -ne 2 ] ; then
    echo $USAGE
    exit 1
fi

if ! [ -f "$CONFIG_FILE" ] ; then
    echo "Cannot open configuration file $CONFIG_FILE"
    exit 1
fi

. $CONFIG_FILE

CONTAINER_NAME=${SEARCH_CONT}

if [ -z "$IMAGE_TAG" ] ; then
    IMAGE_TAG="latest"
fi

HOST_SUPERVISOR_LOG_DIR=${HOST_CONTAINER_LOG_DIR}/${CONTAINER_NAME}/${SUPERVISOR_DIR}
mkdir -p HOST_SUPERVISOR_LOG_DIR
HOST_CLOUDSIGHT_LOG_DIR=${HOST_CONTAINER_LOG_DIR}/${CONTAINER_NAME}/${CLOUDSIGHT_DIR}
mkdir -p HOST_CLOUDSIGHT_LOG_DIR

case $1 in
    start)
        echo "Starting ${CONTAINER_NAME}."
        # Start searchservice
        if [ ! -z "$REGISTRY" ]; then
            set -x
            docker pull $REGISTRY/$SEARCH_IMG:$IMAGE_TAG 2>&1 > /dev/null
            docker tag -f $REGISTRY/$SEARCH_IMG:$IMAGE_TAG $SEARCH_IMG 
            set +x
        fi

        set -x

        docker run -d -p 8885:8885 -e ES_IP=$ELASTIC_HOST_1 -e ES_PORT=$ES_PORT --name   ${CONTAINER_NAME} $SEARCH_IMG 

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
