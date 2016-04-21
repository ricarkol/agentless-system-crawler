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

CONTAINER_NAME=${STATSD_CONT}
INSTANCE_ID=`hostname`:$CONTAINER_NAME

if [ -z "$IMAGE_TAG" ] ; then
    IMAGE_TAG="latest"
fi

case $1 in
    start)
        echo "Starting ${CONTAINER_NAME}."
        if [ ! -z "$REGISTRY" ]; then
            set -x
            docker pull $REGISTRY/$STATSD_IMG:$IMAGE_TAG 2>&1 > /dev/null
            docker tag -f $REGISTRY/$STATSD_IMG:$IMAGE_TAG $STATSD_IMG
            set +x
        fi
        # Pass all of the args to docker as supplied to the config file in deploy-services
        set -x
        docker run -d \
            --restart=always \
            --log-opt max-size=50m --log-opt max-file=5 \
            -p 8125:8125/udp \
            --name ${CONTAINER_NAME} \
            -it $STATSD_IMG \
            -hostname `hostname` \
            -graphite-host $STATSD_ENDPOINT \
            -graphite-port 9095 \
            -graphite-prefix ${LSF_TENANT_ID}.`hostname`. \
            -graphite-tenant-id $LSF_TENANT_ID \
            -graphite-logging-password $LSF_PASSWORD \
            -type statsd
			2>> /var/log/cloudsight/statsd_error.log

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
