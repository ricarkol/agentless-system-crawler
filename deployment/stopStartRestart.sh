#!/bin/bash


#
# Vulnerability Advisor deployment orchestrator
# (c) IBM Research 2015
#

echo "================================================"

if [ $# -eq 2 ]
    then
    echo "Processing all containers"
    PROCESS_ES=true
    PROCESS_VA=true
    PROCESS_UTILS=true
    CONTAINER_NAME=
elif [ $# -eq 3 ]
    then
    if [ "$3" = "all" ]
       then
        echo "Processing all containers (vacore, utils, ES)"
        PROCESS_ES=true
        PROCESS_VA=true
        PROCESS_UTILS=true
        CONTAINER_NAME=
    elif [ "$3" = "vacore" ]
        then
        echo "Processing all VA core containers except ES"
        PROCESS_ES=false
        PROCESS_VA=true
        PROCESS_UTILS=false
        CONTAINER_NAME=
    elif [ "$3" = "utils" ]
        then
        echo "Processing util containers"
        PROCESS_ES=false
        PROCESS_VA=false
        PROCESS_UTILS=true
        CONTAINER_NAME=cloudsight-$3
    else
        echo "Processing container:" $3
        PROCESS_ES=true
        PROCESS_VA=true
        PROCESS_UTILS=true
        CONTAINER_NAME=cloudsight-$3
    fi
else
   echo "Usage: $0 <ENV> < stop | start | restart > [ all | vacore | utils | <CONTAINER_NAME> ]"
   exit 1
fi

ENV=$1
FUNCTION=$2

if  [ "$FUNCTION" != "stop" ] && \
    [ "$FUNCTION" != "start" ] && \
    [ "$FUNCTION" != "restart" ] ; then
    echo "FUNCTION must equal 'stop', 'start' or 'restart'"
    exit 1
fi

echo "Processing ENV ${ENV}"

. ../config/hosts.${ENV}
. ../config/docker-images
. ../config/container_hosts.${ENV}

SSH="ssh -o StrictHostKeyChecking=no"

exit_code=0

ES_HOSTS=""
for count in `seq ${CONTAINER_COUNTS[$ES_CONT]}`
do
    host=${CONTAINER_HOSTS[$ES_CONT.$count]}
    if [ -z "$ES_HOSTS" ] 
        then
        ES_HOSTS=$host
    else
        ES_HOSTS="$ES_HOSTS,$host"
    fi
done

cloudsight_scripts_dir="/opt/cloudsight/kafka-elk-cloudsight"
. ../config/component_configs.sh

Component_STAT=$?
    if [ $Component_STAT -ne 0 ]
        then
        echo "Failed to start $container.$count in $host"
        exit $Component_STAT
    fi


for (( i=${#CONTAINER_STARTUP_ORDER[@]}-1 ; i>=0 ; i-- ))
    do
        container=${CONTAINER_STARTUP_ORDER[i]}
        if [ -z "$CONTAINER_NAME" ] || [ "$CONTAINER_NAME" = $container ]
            then
            CONTAINER_KNOWN="true"
        fi
    done

if [ -z "$CONTAINER_KNOWN" ]
    then
    echo "Containers of type $CONTAINER_NAME unknown"
    exit 1
fi

doit() {
    OPERATION=$1
    echo "------------------------------------------------"
    CONTAINER_KNOWN="true"
    for count in `seq ${CONTAINER_COUNTS[$container]}|sort -r`
    do
        host=${CONTAINER_HOSTS["$container.$count"]}
        config_file=${container}.${count}.sh
        case "$container" in
        $ES_CONT)
            if [ "$PROCESS_ES" = "true" ]
                then
                echo
                echo "Processing $OPERATION $container $count IN $host"
                $SSH ${SSH_USER}@$host /usr/bin/sudo docker $OPERATION ${container}_${count}
                STAT=$?
                exit_code=$((exit_code + STAT))
            fi
        ;;
        $KAFKA_CONT | $INDEXER_CONT | $VULNERABILITY_INDEXER_CONT | $COMPLIANCE_INDEXER_CONT | $NOTIFICATION_INDEXER_CONT | $TIMEMACHINE_CONT | $COMPLIANCE_ANNOTATOR_CONT | $CONFIG_PARSER_CONT | $PASSWORD_ANNOTATOR_CONT | $REGISTRY_MONITOR_CONT)
            if [ "$PROCESS_VA" = "true" ]
                then
                echo
                echo "Processing $OPERATION $container $count IN $host"
                $SSH ${SSH_USER}@$host /usr/bin/sudo docker $OPERATION ${container}_${count}
                STAT=$?
                exit_code=$((exit_code + STAT))
            fi
        ;;
        $USNCRAWLER_CONT | $NOTIFICATION_PROCESSOR_CONT | $VULNERABILITY_ANNOTATOR_CONT | $SEARCH_CONT)
            if [ "$PROCESS_VA" = "true" ]
                then
                echo
                echo "Processing $OPERATION $container $count IN $host"
                $SSH ${SSH_USER}@$host /usr/bin/sudo docker $OPERATION ${container}
                STAT=$?
                exit_code=$((exit_code + STAT))
            fi
        ;;
        $REGISTRY_UPDATE_CONT)
            if [ "$PROCESS_VA" = "true" ]
                then
                echo
                echo "Processing $OPERATION $container $count IN $host"
                $SSH ${SSH_USER}@$host /usr/bin/sudo docker $OPERATION ${container}_${count}
                STAT=$?
                exit_code=$((exit_code + STAT))
                if [ $STAT -eq 0 ] && [ "$OPERATION" = "stop" ]
                    then
                    echo "Sleeping for 15 seconds to starve upstreams before performing additional shutdowns"
                    sleep 15
                fi
            fi
        ;;
        $REGCRAWLER)
            if [ "$PROCESS_VA" = "true" ]
                then
                echo
                echo "Processing $OPERATION $container $count IN $host"
                $SSH ${SSH_USER}@$host /usr/bin/sudo /usr/bin/service regcrawler $OPERATION
                STAT=$?
                exit_code=$((exit_code + STAT))
            fi
        ;;
        $CONSUL_CONT | $IMAGE_RESCANNER_CONT)
            if [ "$PROCESS_UTILS" = "true" ]
                then
                echo
                echo "Processing $OPERATION $container $count IN $host"
                $SSH ${SSH_USER}@$host /usr/bin/sudo docker $OPERATION ${container}_${count}
                STAT=$?
                exit_code=$((exit_code + STAT))
            fi
        ;;
        $METRICS_SERVER_CONT | $CONFIG_AND_METRICS_CRAWLER_CONT)
            if [ "$PROCESS_UTILS" = "true" ]
                then
                echo
                echo "Processing $OPERATION $container $count IN $host"
                # The container count doesn't really apply here as we want it on every host, so I create my own.
                # Count through hosts and stop the config and metrics crawler on every host.
                for host in ${HOSTS[@]}
                    do
                        $SSH ${SSH_USER}@$host /usr/bin/sudo docker $OPERATION ${container}
                        STAT=$?
                        exit_code=$((exit_code + STAT))
                    done
            fi
        ;;
        *)
            echo "Containers of type $container not yet supported"
        ;;
        esac
    done
}

if [ "$FUNCTION" = "stop" ] || [ "$FUNCTION" = "restart" ]
    then
    echo ""
    echo "================================================"
    echo "Shutting down specified services."

    #shutting down services
    for (( i=${#CONTAINER_STARTUP_ORDER[@]}-1 ; i>=0 ; i-- ))
    do
        container=${CONTAINER_STARTUP_ORDER[i]}
#        echo "$CONTAINER_NAME $container"
        if [ -z "$CONTAINER_NAME" ] || [ "$CONTAINER_NAME" = $container ]
            then
            doit "stop"
        fi
    done
fi

if [ "$FUNCTION" = "start" ] || [ "$FUNCTION" = "restart" ]
    then
    echo ""
    echo "================================================"
    echo "Starting up all specified services."

    #starting up services
    for container in ${CONTAINER_STARTUP_ORDER[@]}
    do
        if [ -z "$CONTAINER_NAME" ] || [ "$CONTAINER_NAME" = $container ]
            then
            doit "start"
        fi
    done
fi

echo ""
echo "================================================"

if [ $exit_code -eq 0 ]
    then
    echo "Vulnerability Advisor $2 - PASS!"
    echo "================================================"
else
    echo "Vulnerability Advisor $2 failed for at least one container - FAIL!"
    echo "Check the logs for more details"
    echo "================================================"
    exit 1
fi
