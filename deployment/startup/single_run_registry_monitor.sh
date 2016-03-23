#!/bin/bash

. $CONFIG_FILE

INSTANCE_ID=`hostname`_${CONTAINER_NAME}
HOST_CLOUDSIGHT_LOG_DIR=${HOST_CONTAINER_LOG_DIR}/${CONTAINER_NAME}/${CLOUDSIGHT_DIR}
mkdir -p HOST_CLOUDSIGHT_LOG_DIR

old_container_id=`docker ps -a --format {{.ID}}  --filter "name=single-run-cloudsight-registry-monitor"`

rm -rf $REGCRAWL_HOST_DATA_DIR
mkdir -p $REGCRAWL_HOST_DATA_DIR

if [ -z "$old_container_id" ]; then
    docker rm -f $old_container_id
fi
echo "Starting ${CONTAINER_NAME}."
if [ ! -z "$REGISTRY" ]; then
    set -x
    docker pull $REGISTRY/$REGISTRY_MONITOR_IMG:$IMAGE_TAG 2>&1 > /dev/null
    docker tag -f $REGISTRY/$REGISTRY_MONITOR_IMG:$IMAGE_TAG $REGISTRY_MONITOR_IMG 
    set +x
fi

mkdir -p $REGCRAWL_HOST_DATA_DIR

echo "docker run -d  \
     "-v ${REGCRAWL_HOST_DATA_DIR}:${REGCRAWL_GUEST_DATA_DIR}" \
     "-v ${HOST_CLOUDSIGHT_LOG_DIR}:${CONTAINER_CLOUDSIGHT_LOG_DIR}" \
     "--name $CONTAINER_NAME $REGISTRY_MONITOR_IMG --user $REGISTRY_USER" \
     "--password xxxxx --email $REGISTRY_EMAIL --org $BLUEMIX_ORG" \
     "--space $BLUEMIX_SPACE --single-run True \
     "--ice-api $REGISTRY_ICE_API --insecure-registry $INSECURE_REGISTRY" \
     "$REGISTRY_URL $KAFKA_SERVICE"

# Start registry-monitor
docker run -d  \
           -v ${REGCRAWL_HOST_DATA_DIR}:${REGCRAWL_GUEST_DATA_DIR} \
           -v ${HOST_CLOUDSIGHT_LOG_DIR}:${CONTAINER_CLOUDSIGHT_LOG_DIR} \
           --name "$CONTAINER_NAME" \
           "$REGISTRY_MONITOR_IMG" --user "$REGISTRY_USER" --password "$REGISTRY_PASSWORD" \
           --email "$REGISTRY_EMAIL" --org "$BLUEMIX_ORG" --space "$BLUEMIX_SPACE" \
           --single-run True --ice-api "$REGISTRY_ICE_API" \
           --insecure-registry "$INSECURE_REGISTRY" \
           "$REGISTRY_URL" "$KAFKA_SERVICE"

STAT=$?
exit $STAT

