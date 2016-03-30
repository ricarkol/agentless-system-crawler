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

CONTAINER_NAME=${CONFIG_AND_METRICS_CRAWLER_CONT}
INSTANCE_ID=`hostname`:$CONTAINER_NAME

if [ -z "$IMAGE_TAG" ] ; then
    IMAGE_TAG="latest"
fi

HOST_SUPERVISOR_LOG_DIR=${HOST_CONTAINER_LOG_DIR}/${CONTAINER_NAME}/${SUPERVISOR_DIR}
HOST_CLOUDSIGHT_LOG_DIR=${HOST_CONTAINER_LOG_DIR}/${CONTAINER_NAME}/${CLOUDSIGHT_DIR}
mkdir -p HOST_SUPERVISOR_LOG_DIR
mkdir -p HOST_CLOUDSIGHT_LOG_DIR
mkdir -p HOST_CONFIG_AND_METRICS_CRAWLER_SNAPSHOTS_DIR

case $1 in
    start)
        echo "Starting ${CONTAINER_NAME}."
        if [ ! -z "$REGISTRY" ]; then
            set -x
            docker pull $REGISTRY/$CONFIG_AND_METRICS_CRAWLER_IMG:$IMAGE_TAG 2>&1 > /dev/null
            docker tag -f $REGISTRY/$CONFIG_AND_METRICS_CRAWLER_IMG:$IMAGE_TAG $CONFIG_AND_METRICS_CRAWLER_IMG
            set +x
        fi
        # Pass all of the args to docker as supplied to the config file in deploy-services
        set -x
        docker run -d --privileged --net=host --pid=host \
            --restart=always \
            --log-opt max-size=50m --log-opt max-file=5 \
			-v /cgroup:/cgroup \
			-v /sys/fs/cgroup:/sys/fs/cgroup \
			-v /var/run/docker.sock:/var/run/docker.sock \
			-v ${HOST_SUPERVISOR_LOG_DIR}:${CONTAINER_SUPERVISOR_LOG_DIR} \
			-v ${HOST_CONTAINER_LOG_DIR}:${CONTAINER_CLOUDSIGHT_LOG_DIR} \
			-v ${HOST_CONFIG_AND_METRICS_CRAWLER_SNAPSHOTS_DIR}:${CONTAINER_CONFIG_AND_METRICS_CRAWLER_SNAPSHOTS_DIR} \
			--name ${CONTAINER_NAME} \
			-it $CONFIG_AND_METRICS_CRAWLER_IMG \
			--url "$CONFIG_AND_METRICS_CRAWLER_EMIT_URL" "file://${CONTAINER_CONFIG_AND_METRICS_CRAWLER_SNAPSHOTS_DIR}/stats" \
			--overwrite \
			--since EPOCH \
			--frequency "$CONFIG_AND_METRICS_CRAWLER_FREQ" \
			--features "$CONFIG_AND_METRICS_CRAWLER_FEATURES" \
			--compress false \
			--logfile ${CONTAINER_CLOUDSIGHT_LOG_DIR}/config-and-metrics-crawler-containers.log \
			--crawlContainers ALL \
			--format "$CONFIG_AND_METRICS_CRAWLER_FORMAT" \
			--crawlmode "$CONFIG_AND_METRICS_CRAWLER_MODE" \
			--environment "$CONFIG_AND_METRICS_CRAWLER_ENVIRONMENT" \
			--numprocesses "$NUM_CORES" \
			--namespace ${CONFIG_AND_METRICS_CRAWLER_SPACE_ID}.va.`hostname` \
			2>> ${CONTAINER_CLOUDSIGHT_LOG_DIR}config-and-metrics-crawler-containers-error.log

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
