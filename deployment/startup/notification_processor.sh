#!/bin/bash

#CONFIG_FILE=setup_env.sh

USAGE="Usage $0 start|stop|delete"

if [ $# -ne 2 ] ; then
    echo $USAGE
    exit 1
fi

if ! [ -f "$CONFIG_FILE" ] ; then
    echo "Cannot open configuration file $CONFIG_FILE"
    exit 1
fi

. $CONFIG_FILE
PROC_ID=$2
CONTAINER_NAME=${NOTIFICATION_PROCESSOR_CONT}
INSTANCE_ID=`hostname`:${NOTIFICATION_PROCESSOR_CONT}_${PROC_ID}

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
            docker pull $REGISTRY/$NOTIFICATION_PROCESSOR_IMG:$IMAGE_TAG 2>&1 > /dev/null
            docker tag -f $REGISTRY/$NOTIFICATION_PROCESSOR_IMG:$IMAGE_TAG $NOTIFICATION_PROCESSOR_IMG 
            set +x
        fi
        # Start notification processor
        set -x
        docker run -d --restart=always \
            -v ${HOST_SUPERVISOR_LOG_DIR}:${CONTAINER_SUPERVISOR_LOG_DIR} \
            -v ${HOST_CLOUDSIGHT_LOG_DIR}:${CONTAINER_CLOUDSIGHT_LOG_DIR} \
            --name ${CONTAINER_NAME} ${NOTIFICATION_PROCESSOR_IMG} \
            --elasticsearch-url $ELASTIC_HOST_1:$ES_PORT --processor-id $PROC_ID \
            --notification-topic notification  --kafka-url $KAFKA_SERVICE \
            --kafka-zookeeper-port ${KAFKA_ZOOKEEPER_PORT}

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
