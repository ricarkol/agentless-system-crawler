#!/bin/bash

#CONFIG_FILE=setup_env.sh

USAGE="Usage $0 start|stop|delete 1|2"

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
CONTAINER_NAME=${KAFKA_CONT}_${PROC_ID}
KAFKA_DIR_CONTAINER='/opt/kafka/logs'

if [ -z "$IMAGE_TAG" ] ; then
    IMAGE_TAG="latest"
fi

HOST_SUPERVISOR_LOG_DIR=${HOST_CONTAINER_LOG_DIR}/${CONTAINER_NAME}/${SUPERVISOR_DIR}
HOST_CLOUDSIGHT_LOG_DIR=${HOST_CONTAINER_LOG_DIR}/${CONTAINER_NAME}/${CLOUDSIGHT_DIR}
mkdir -p HOST_SUPERVISOR_LOG_DIR
mkdir -p HOST_CLOUDSIGHT_LOG_DIR

# To enable multiple kafkas and zookeepers to run on same host
HOST_KAFKA_PORT=${PROC_ID}${KAFKA_PORT}
CONTAINER_KAFKA_PORT=$HOST_KAFKA_PORT
HOST_KAFKA_ZOOKEEPER_PORT=${PROC_ID}${KAFKA_ZOOKEEPER_PORT}
CONTAINER_KAFKA_ZOOKEEPER_PORT=$KAFKA_ZOOKEEPER_PORT

# To enable multiple kafkas and zookeepers to run on same host
HOST_KAFKA_JMX_PORT=${PROC_ID}$KAFKA_JMX_PORT
CONTAINER_KAFKA_JMX_PORT=${PROC_ID}$KAFKA_JMX_PORT
HOST_KAFKA_ZOOKEEPER_JMX_PORT=${PROC_ID}$KAFKA_ZOOKEEPER_JMX_PORT
CONTAINER_KAFKA_ZOOKEEPER_JMX_PORT=${PROC_ID}$KAFKA_ZOOKEEPER_JMX_PORT

ZOOKEEPER_CLUSTER=
server_num=1
for host in ${KAFKA_CLUSTER[@]} ; do
   ZOOKEEPER_CLUSTER=${ZOOKEEPER_CLUSTER},${host}:${server_num}$KAFKA_ZOOKEEPER_PORT
   server_num=$((server_num+1))
done
ZOOKEEPER_CLUSTER=${ZOOKEEPER_CLUSTER:1}

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

        docker run -d --restart=always -p $HOST_KAFKA_PORT:$CONTAINER_KAFKA_PORT  \
                   --log-opt max-size=50m --log-opt max-file=5 \
                   -p $HOST_KAFKA_ZOOKEEPER_PORT:$CONTAINER_KAFKA_ZOOKEEPER_PORT \
                   -p $HOST_KAFKA_JMX_PORT:$CONTAINER_KAFKA_JMX_PORT \
                   -p $HOST_KAFKA_ZOOKEEPER_JMX_PORT:$CONTAINER_KAFKA_ZOOKEEPER_JMX_PORT \
                   -p ${PROC_ID}2888:2888 \
                   -p ${PROC_ID}3888:3888 \
                   -e HOST_IP=$KAFKA_HOST \
                   -e ZOOKEEPER_CLUSTER=$ZOOKEEPER_CLUSTER \
                   -e PROC_ID=$PROC_ID \
                   -e KAFKA_PORT=$KAFKA_PORT \
                   -e KAFKA_MAX_MSG_SIZE=$KAFKA_MAX_MSG_SIZE \
                   -e KAFKA_JMX_PORT=$CONTAINER_KAFKA_JMX_PORT \
                   -e KAFKA_ZOOKEEPER_PORT=$KAFKA_ZOOKEEPER_PORT \
                   -e KAFKA_ZOOKEEPER_JMX_PORT=$CONTAINER_KAFKA_ZOOKEEPER_JMX_PORT \
                   -v $KAFKA_DATA_VOLUME/kafka-logs:/tmp/kafka-logs \
                   -v $KAFKA_DATA_VOLUME/zookeeper:/tmp/zookeeper \
                   -v $HOST_SUPERVISOR_LOG_DIR:$CONTAINER_SUPERVISOR_LOG_DIR  \
	                 -v $HOST_CLOUDSIGHT_LOG_DIR:$CONTAINER_CLOUDSIGHT_LOG_DIR \
                   --name ${CONTAINER_NAME} $KAFKA_IMG

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
