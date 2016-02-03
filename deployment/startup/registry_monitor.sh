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
CONTAINER_NAME=${REGISTRY_MONITOR_CONT}_${PROC_ID}
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
            docker pull $REGISTRY/$REGISTRY_MONITOR_IMG:$IMAGE_TAG 2>&1 > /dev/null
            docker tag -f $REGISTRY/$REGISTRY_MONITOR_IMG:$IMAGE_TAG $REGISTRY_MONITOR_IMG 
            set +x
        fi

        mkdir -p $REGCRAWL_HOST_DATA_DIR

        echo "docker run -d --restart=always" \
             "-v ${REGCRAWL_HOST_DATA_DIR}:${REGCRAWL_GUEST_DATA_DIR}" \
             "-v ${HOST_CLOUDSIGHT_LOG_DIR}:${CONTAINER_CLOUDSIGHT_LOG_DIR}" \
             "--name $CONTAINER_NAME $REGISTRY_MONITOR_IMG --user $REGISTRY_USER" \
             "--password xxxxx --email $REGISTRY_EMAIL --org $BLUEMIX_ORG" \
             "--space $BLUEMIX_SPACE --single-run $REGISTRY_MONITOR_SINGLE_RUN" \
             "--ice-api $REGISTRY_ICE_API --insecure-registry $INSECURE_REGISTRY" \
             "--alchemy-registry-api $ALCHEMY_REGISTRY_URL" \
             "--elasticsearch-url $ELASTIC_HOST_1:$ES_PORT" \
             "$REGISTRY_URL $KAFKA_SERVICE --instance-id $INSTANCE_ID"

        # Start registry-monitor
        docker run -m=${MAX_CONTAINER_MEMORY} -d --restart=always \
                   -v ${REGCRAWL_HOST_DATA_DIR}:${REGCRAWL_GUEST_DATA_DIR} \
                   -v ${HOST_CLOUDSIGHT_LOG_DIR}:${CONTAINER_CLOUDSIGHT_LOG_DIR} \
                   --name "$CONTAINER_NAME" \
                   "$REGISTRY_MONITOR_IMG" --user "$REGISTRY_USER" --password "$REGISTRY_PASSWORD" \
                   --email "$REGISTRY_EMAIL" --org "$BLUEMIX_ORG" --space "$BLUEMIX_SPACE" \
                   --single-run "$REGISTRY_MONITOR_SINGLE_RUN" --ice-api "$REGISTRY_ICE_API" \
                   --insecure-registry "$INSECURE_REGISTRY" --alchemy-registry-api "$ALCHEMY_REGISTRY_URL" \
                   --elasticsearch-url "$ELASTIC_HOST_1:$ES_PORT" \
                   "$REGISTRY_URL" "$KAFKA_SERVICE" --instance-id "$INSTANCE_ID"
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
