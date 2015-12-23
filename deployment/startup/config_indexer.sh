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
INSTANCE_ID=`hostname`_${PROC_ID}
CONTAINER_NAME=${INDEXER_CONT}_${PROC_ID}

if [ -z "$IMAGE_TAG" ] ; then
    IMAGE_TAG="latest"
fi

HOST_SUPERVISOR_LOG_DIR=${HOST_CONTAINER_LOG_DIR}/${CONTAINER_NAME}/${SUPERVISOR_DIR}
mkdir -p HOST_SUPERVISOR_LOG_DIR

case $1 in
    start)
        echo "Starting ${CONTAINER_NAME}."
        if [ ! -z "$REGISTRY" ]; then
            set -x
            docker pull $REGISTRY/$INDEXER_IMG:$IMAGE_TAG 2>&1 > /dev/null
            docker tag -f $REGISTRY/$INDEXER_IMG:$IMAGE_TAG $INDEXER_IMG 
            set +x
        fi
        # Start the config indexer
        set -x
        docker run -d --restart=always -e HOST_IP=$ELASTIC_HOST_1 -e ZK_IP=$KAFKA_HOST \
            -e LS_HEAP_SIZE=$LS_HEAP_SIZE  -e PROCESSOR_ID=config_indexer_$PROC_ID \
            -e KAFKA_MAX_MSG_SIZE=$KAFKA_MAX_MSG_SIZE -e INSTANCE_ID=${INSTANCE_ID} \
            -e CONTAINER_NAME=`hostname`:${CONTAINER_NAME} \
            -v ${HOST_SUPERVISOR_LOG_DIR}:${CONTAINER_SUPERVISOR_LOG_DIR} \
            --name $CONTAINER_NAME  $INDEXER_IMG

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
