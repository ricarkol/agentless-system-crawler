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

CONTAINER_NAME=${MT_LOGSTASH_FORWARDER_CONT}
INSTANCE_ID=`hostname`:$CONTAINER_NAME

if [ -z "$IMAGE_TAG" ] ; then
    IMAGE_TAG="latest"
fi

case $1 in
    start)
        echo "Starting ${CONTAINER_NAME}."
        if [ ! -z "$REGISTRY" ]; then
            set -x
            docker pull $REGISTRY/$MT_LOGSTASH_FORWARDER_IMG:$IMAGE_TAG 2>&1 > /dev/null
            docker tag -f $REGISTRY/$MT_LOGSTASH_FORWARDER_IMG:$IMAGE_TAG $MT_LOGSTASH_FORWARDER_IMG
            set +x
        fi
        # Pass all of the args to docker as supplied to the config file in deploy-services
        set -x
        docker run -d --net=host --pid=host \
            --restart=always \
			-v /var/log:/var/log \
			-v /mnt/data/elasticsearch:/mnt/data/elasticsearch \
			--name ${CONTAINER_NAME} \
			-it $MT_LOGSTASH_FORWARDER_IMG \
			${LSF_SPACE_ID} \
			${LSF_PASSWORD} \
			${LSF_ORGANISATION} \
			${LSF_SPACE_NAME} \
            ${LSF_TARGET} \
			2>> /var/log/cloudsight/mt-logstash-forwarder.log
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