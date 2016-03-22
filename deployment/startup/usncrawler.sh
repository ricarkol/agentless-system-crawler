#!/bin/bash

#CONFIG_FILE=setup_env.sh

USAGE="Usage $0 start|stop|delete"

if [ $# -ne 1 ] ; then
    echo $USAGE
    exit 1
fi

if ! [ -f "$CONFIG_FILE" ] ; then
    echo "Cannot open configuration file $CONFIG_FILE"
    exit 1
fi

. $CONFIG_FILE

CONTAINER_NAME=${USNCRAWLER_CONT}

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
        # Start usncrawler
        if [ ! -z "$REGISTRY" ]; then
            set -x
            docker pull $REGISTRY/$USN_CRAWLER_IMG:$IMAGE_TAG 2>&1 > /dev/null
            docker tag -f $REGISTRY/$USN_CRAWLER_IMG:$IMAGE_TAG $USN_CRAWLER_IMG 
            set +x
        fi

        set -x
        docker run -d --restart=always  \
             -v $USN_CRAWLER_DATA_DIR:/opt/usncrawler/sec_data \
             -v ${HOST_SUPERVISOR_LOG_DIR}:${CONTAINER_SUPERVISOR_LOG_DIR} \
             -v ${HOST_CLOUDSIGHT_LOG_DIR}:${CONTAINER_CLOUDSIGHT_LOG_DIR} \
             --name ${CONTAINER_NAME} $USN_CRAWLER_IMG \
             --elastic-search $ELASTIC_HOST_1:$ES_PORT \
             --data-root /opt/usncrawler/sec_data --sleeptime $USN_CRAWLER_SLEEP_TIME

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
