#!/bin/bash


USAGE="Usage $0 start|stop|delete container_number"

MAX_CONTAINER_MEMORY="8G"

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
CONTAINER_NAME=${REGISTRY_UPDATE_CONT}_${PROC_ID}
INSTANCE_ID=`hostname`_${CONTAINER_NAME}

if [ -z "$IMAGE_TAG" ] ; then
    IMAGE_TAG="latest"
fi

HOST_CLOUDSIGHT_LOG_DIR=${HOST_CONTAINER_LOG_DIR}/${CONTAINER_NAME}/${CLOUDSIGHT_DIR}
mkdir -p HOST_CLOUDSIGHT_LOG_DIR

case $1 in
    start)
        echo "Starting ${CONTAINER_NAME}."
        if [ ! -z "$REGISTRY" ]; then
            set -x
            docker pull $REGISTRY/$REGISTRY_UPDATE_IMG:$IMAGE_TAG 2>&1 > /dev/null
            docker tag -f $REGISTRY/$REGISTRY_UPDATE_IMG:$IMAGE_TAG $REGISTRY_UPDATE_IMG 
            set +x
        fi
        # Start registry-update
        set -x
        docker run -m=${MAX_CONTAINER_MEMORY} \
                   -d --restart=always -p "$REGISTRY_UPDATE_PORT:$REGISTRY_UPDATE_PORT" \
                   -v ${HOST_CLOUDSIGHT_LOG_DIR}:${CONTAINER_CLOUDSIGHT_LOG_DIR} \
                   --name "$CONTAINER_NAME" "$REGISTRY_UPDATE_IMG" \
                   --listen-port "$REGISTRY_UPDATE_PORT" --kafka-service "$KAFKA_SERVICE"
        set +x
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
