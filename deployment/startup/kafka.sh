#!/bin/bash

#CONFIG_FILE=setup_env.sh

USAGE="Usage $0 start|stop|delete 1|2"

if [ $# -ne 2 ] ; then
    echo $USAGE
    exit 1
fi

re='^[1-2]$'
if ! [[ $2 =~ $re ]] ; then
   echo "error: kafka instance number must be in [1-2] " >&2; exit 1
fi

if ! [ -f "$CONFIG_FILE" ] ; then
    echo "Cannot open configuration file $CONFIG_FILE"
    exit 1
fi

. $CONFIG_FILE

PROC_ID=$2
CONTAINER_NAME=${KAFKA_CONT}_${PROC_ID}
KAFKA_DIR_CONTAINER='/opt/kafka/logs'

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
            docker pull $REGISTRY/$KAFKA_IMG:$IMAGE_TAG 2>&1 > /dev/null
            docker tag -f $REGISTRY/$KAFKA_IMG:$IMAGE_TAG $KAFKA_IMG 
            set +x
        fi
        # Start Kafka
        set -x

        docker run -d --restart=always -p $KAFKA_PORT:$KAFKA_PORT  \
                   -p $KAFKA_ZOO_KEEPER_PORT:$KAFKA_ZOO_KEEPER_PORT \
                   -e HOST_IP=$KAFKA_HOST \
                   -e KAFKA_MAX_MSG_SIZE=$KAFKA_MAX_MSG_SIZE \
                   -v $KAFKA_DATA_VOLUME:/tmp/kafka-logs \
                   -v $HOST_SUPERVISOR_LOG_DIR:$CONTAINER_SUPERVISOR_LOG_DIR  \
	           -v $HOST_CLOUDSIGHT_LOG_DIR:$CONTAINER_CLOUDSIGHT_LOG_DIR \
                   --name ${CONTAINER_NAME} $KAFKA_IMG
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
