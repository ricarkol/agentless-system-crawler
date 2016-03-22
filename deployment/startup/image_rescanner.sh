#!/bin/bash

#CONFIG_FILE=setup_env.sh

USAGE="Usage $0 start|stop|delete container_number"

if [ $# -ne 2 ] ; then
    echo $USAGE
    exit 1
fi

re='^[0-9]+$'
if ! [[ $2 =~ $re ]] ; then
   echo "error: container_number must be an integer" >&2; exit 1
fi

if ! [ -f "$CONFIG_FILE" ] ; then
    echo "Cannot open configuration file $CONFIG_FILE"
    exit 1
fi

. $CONFIG_FILE

PROC_ID=$2
CONTAINER_NAME=${IMAGE_RESCANNER_CONT}_$PROC_ID
INSTANCE_ID=`hostname`:${CONTAINER_NAME}

if [ -z "$IMAGE_TAG" ] ; then
    IMAGE_TAG="latest"
fi

HOST_SUPERVISOR_LOG_DIR=${HOST_CONTAINER_LOG_DIR}/${CONTAINER_NAME}/${SUPERVISOR_DIR}
HOST_CLOUDSIGHT_LOG_DIR=${HOST_CONTAINER_LOG_DIR}/${CONTAINER_NAME}/${CLOUDSIGHT_DIR}
mkdir -p HOST_SUPERVISOR_LOG_DIR
mkdir -p HOST_CLOUDSIGHT_LOG_DIR

case $1 in
    start)
        echo "Starting ${CONTAINER_NAME}."
        if [ ! -z "$REGISTRY" ]; then
            set -x
            docker pull $REGISTRY/$IMAGE_RESCANNER_IMG:$IMAGE_TAG 2>&1 > /dev/null
            docker tag -f $REGISTRY/$IMAGE_RESCANNER_IMG:$IMAGE_TAG $IMAGE_RESCANNER_IMG 
            set +x
        fi
        # start image rescanner
        set -x		
        docker run -d --restart=always \
            -v ${HOST_SUPERVISOR_LOG_DIR}:${CONTAINER_SUPERVISOR_LOG_DIR} \
            -v ${HOST_CLOUDSIGHT_LOG_DIR}:${CONTAINER_CLOUDSIGHT_LOG_DIR} \
             --name $CONTAINER_NAME \
            ${IMAGE_RESCANNER_IMG} --elasticsearch-url $ELASTIC_HOST_1:$ES_PORT --regcrawl1-ip $REGCRAWL1 --regcrawl2-ip $REGCRAWL2 --regcrawl3-ip $REGCRAWL3

        STAT=$?
        set +x
        exit $STAT
        ;;

   stop)
        echo -n "Stopping container: " ${CONTAINER_NAME}
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
