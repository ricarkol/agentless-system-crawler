#!/usr/bin/env bash

#`CONFIG_FILE=setup_env.sh

USAGE="Usage $0 start|stop|delete"

# Start the crawler as a container.

# Arguments passed to this script will be passed to the crawler.

if [ $# -ne 1 ] ; then
    echo $USAGE
    exit 1
fi

if ! [ -f "$CONFIG_FILE" ] ; then
    echo "Cannot open configuration file $CONFIG_FILE"
    exit 1
fi

. $CONFIG_FILE

CONTAINER_NAME=${UPTIME_SERVER_CONT}
INSTANCE_ID=`hostname`:$CONTAINER_NAME

if [ -z "$IMAGE_TAG" ] ; then
    IMAGE_TAG="latest"
fi

case $1 in
    start)
        echo "Starting ${CONTAINER_NAME}."
        if [ ! -z "$REGISTRY" ]; then
            set -x
            docker pull $REGISTRY/$UPTIME_SERVER_IMG:$IMAGE_TAG 2>&1 > /dev/null
            docker tag -f $REGISTRY/$UPTIME_SERVER_IMG:$IMAGE_TAG $UPTIME_SERVER_IMG
            set +x
        fi
        # Pass all of the args to docker as supplied to the config file in deploy-services
        set -x
        docker run -d \
            --restart=always \
            -p 8586:8586 \
			--name ${CONTAINER_NAME} \
			-it $UPTIME_SERVER_IMG \
			--hosts ${CLOUDSIGHT_HOSTS[@]} \
			--host ${UPTIME_SERVER_NODE_NAME} \
			2>> ${CONTAINER_CLOUDSIGHT_LOG_DIR}/metrics_server_error.log
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
