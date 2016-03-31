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
SERVICE_NAME="va-registry-update"
hostname=`hostname`
CONSUL_NODE=${hostname##${hostname:0:1}*vuln-}
CONSUL_AGENT_HOST_IP=${REGISTRY_UPDATE_IP}

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
        exit_code=0
        set -x
        docker run -m=${MAX_CONTAINER_MEMORY} \
                   -d --restart=always -p "$REGISTRY_UPDATE_PORT:$REGISTRY_UPDATE_PORT" \
                   -e KAFKA_SERVICE=${KAFKA_SERVICE} \
                   -e BLACKLIST_DIR=${CONTAINER_BLACKLIST_DIR} \
                   -e BLACKLIST_FILENAME=${BLACKLIST_FILENAME} \
                   -e INSTANCE_ID=${INSTANCE_ID} \
                   -e LOG_DIR=${CONTAINER_CLOUDSIGHT_LOG_DIR} \
                   -v ${HOST_CLOUDSIGHT_LOG_DIR}:${CONTAINER_CLOUDSIGHT_LOG_DIR} \
                   -v ${HOST_BLACKLIST_DIR}:${CONTAINER_BLACKLIST_DIR} \
                   --name "$CONTAINER_NAME" "$REGISTRY_UPDATE_IMG"
        STAT=$?
        exit_code=$((exit_code + STAT))

        # Register with consul
        curl -s -X PUT \
                -d "{\"name\":\"$SERVICE_NAME\", \"tags\": [ \"$CONSUL_NODE\" ], \"address\":\"$REGISTRY_UPDATE_IP\",\"port\":$REGISTRY_UPDATE_PORT, \"check\": { \"name\": \"$SERVICE_NAME-health\", \"http\": \"http://${REGISTRY_UPDATE_IP}:${REGISTRY_UPDATE_PORT}/registry/health\", \"interval\": \"10s\" } }" \
  http://$CONSUL_AGENT_HOST_IP:8500/v1/agent/service/register

        STAT=$?
        exit_code=$((exit_code + STAT))

        set +x
        exit $exit_code
        ;;

   stop)
        echo -n "Stopping container: "
        echo curl -s -X DELETE http://$CONSUL_AGENT_HOST_IP:8500/v1/agent/service/deregister/$SERVICE_NAME
             curl -s -X DELETE http://$CONSUL_AGENT_HOST_IP:8500/v1/agent/service/deregister/$SERVICE_NAME
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
