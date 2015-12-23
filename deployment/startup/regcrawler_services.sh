#!/bin/bash

CONFIG_FILE=/opt/cloudsight/collector/regcrawler/regcrawler-config.sh

USAGE="Usage $0 start|stop|delete"

if [ $# -ne 1 ] ; then
    echo $USAGE
    exit 1
fi

if ! [ -f "$CONFIG_FILE" ] ; then
    echo "Cannot open configuration file $CONFIG_FILE"
    exit 1
fi

. $CONFIG_FILE


case $1 in
    start)
        echo "Starting registry monitoring services."
        echo "Ensure that regcrawler is listening for events with:" \
             "'service regcrawler start'"
        echo "You can abort the current task and start regcrawler first"
        set -x
        sleep 5
        set +x
        
        if [ "$ICE_API" = "True" ] && [ -z "$REGISTRY_USER" ] ; then
            echo "ICE_API requires REGISTRY_USER to be set"
            exit 1
        fi
 
        if [ -n "$REGISTRY_USER" ]  && ( [ -z "$REGISTRY_PASSWORD" ] || [ -z "$REGISTRY_EMAIL" ] ) ; then
            echo "Registry authentication requires REGISTRY_PASSWORD and REGISTRY_EMAIL fields in $CONFIG_FILE"
            exit 1
        fi


        #registry-update service
        if [ "$RUN_REGISTRY_UPDATE" = "True" ] ; then
            if [ ! -z "$REGISTRY" ]; then
                set -x
                docker pull $REGISTRY/$REGISTRY_UPDATE_IMG 2>&1 > /dev/null
                docker tag -f $REGISTRY/$REGISTRY_UPDATE_IMG $REGISTRY_UPDATE_IMG 
                set +x
            fi

            set -x
            docker run -d -p "$REGISTRY_UPDATE_PORT:$REGISTRY_UPDATE_PORT" \
                       --name "$REGISTRY_UPDATE_CONT" "$REGISTRY_UPDATE_IMG" \
                       --listen-port "$REGISTRY_UPDATE_PORT" --kafka-service "$KAFKA_SERVICE"
            set +x
        fi

        #registry-monitor service
        if [ ! -z "$REGISTRY" ]; then
            docker pull $REGISTRY/$REGISTRY_MONITOR_IMG 2>&1 > /dev/null
            docker tag -f $REGISTRY/$REGISTRY_MONITOR_IMG $REGISTRY_MONITOR_IMG 
        fi

        docker run -d --name "$REGISTRY_MONITOR_CONT" \
                   -v "$REGCRAWL_HOST_DATA_DIR:$REGCRAWL_GUEST_DATA_DIR" \
                   "$REGISTRY_MONITOR_IMG" --user "$REGISTRY_USER" --password "$REGISTRY_PASSWORD" \
                   --email "$REGISTRY_EMAIL" --org "$BLUEMIX_ORG" --space "$BLUEMIX_SPACE" \
                   --single-run "$REGISTRY_MONITOR_SINGLE_RUN" --ice-api "$ICE_API" \
                   --insecure-registry "$INSECURE_REGISTRY" \
                   "$REGISTRY_URL" "$KAFKA_SERVICE"
        ;;
   stop)
        echo "Stopping registry monitoring containers:"
        echo "----------------------------------------"
        docker stop "$REGISTRY_MONITOR_CONT"
        
        if [ "$RUN_REGISTRY_UPDATE" = "True" ] ; then
            docker stop "$REGISTRY_UPDATE_CONT"
        fi
        ;;
   delete)
        echo "Removing registry monitoring containers:"
        echo "----------------------------------------"
        docker rm "$REGISTRY_MONITOR_CONT"
        
        if [ "$RUN_REGISTRY_UPDATE" = "True" ] ; then
            docker rm "$REGISTRY_UPDATE_CONT"
        fi
        ;;
   *)
        echo $USAGE
        exit 1
        ;;
esac
