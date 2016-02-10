#!/bin/bash


#
# Vulnerability Advisor deployment orchestrator
# (c) IBM Research 2015
#

if [ $# -eq 3 ]
    then
    echo "Processing all containers"
    IGNORE_ES=false
    CONTAINER_NAME=
elif [ $# -eq 4 ]
    then
    if [ "$4" = "true" ]
       then
        echo "Processing all containers except ES"
        IGNORE_ES=true
        CONTAINER_NAME=
    elif [ "$4" = "false" ]
        then
        echo "Processing all containers"
        IGNORE_ES=false
        CONTAINER_NAME=
    else
        echo "Processing container:" $4
        IGNORE_ES=false
        CONTAINER_NAME=cloudsight-$4
    fi
else
   echo "Usage: $0 <ENV> <IMAGE_TAG> <DEPLOY_POLICY> [<IGNORE_ES> | <CONTAINER_NAME>]"
   exit 1
fi

ENV=$1
IMAGE_TAG=$2
DEPLOY_POLICY=$3

if  [ "$DEPLOY_POLICY" != "redeploy" ] && \
    [ "$DEPLOY_POLICY" != "shutdown" ] && \
    [ "$DEPLOY_POLICY" != "deploy" ] ; then
    echo "DEPLOY_POLICY must equal 'redeploy', 'shutdown' or 'deploy'"
    exit 1
fi

echo "Deploying to ENV ${ENV}"
echo "IMAGE_TAG: $IMAGE_TAG"

. ../config/hosts.${ENV}
. ../config/docker-images
. ../config/container_hosts.${ENV}

SCP="scp -o StrictHostKeyChecking=no"
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

#assign write nodes top to bottom. Reads are assigned bottom up
balanced_cluster_node(){
    if [ $# -ne 2 ]
        then
        echo "function balanced_cluster_node takes two arguments num_nodes and count"
        return 1
    fi
    num_nodes=$1
    client_num=$2

    echo "Finding balanced node for client # $client_num on cluster of $num_nodes nodes"
    if [ $num_nodes -eq 0 ] 
        then
        target_node=1
    else
        if [ "$client_num" -gt "$num_nodes" ]
            then
            client_num=$(($client_num % $num_nodes))
        fi

        target_node=$(((($num_nodes - $client_num) % $num_nodes) + 1))

        if [ $target_node -eq 0 ] 
            then
            target_node=$num_nodes
        fi
    fi

    echo "Target node is $target_node"
    return 0
}

echo $CONTAINER_STARTUP_ORDER
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

if [ "$DEPLOY_POLICY" != "deploy" ]
    then
    echo "Shutting down all specified services."

    #shutting down services
    for (( i=${#CONTAINER_STARTUP_ORDER[@]}-1 ; i>=0 ; i-- ))
    do
        container=${CONTAINER_STARTUP_ORDER[i]}
        if [ -z "$CONTAINER_NAME" ] || [ "$CONTAINER_NAME" = $container ]
            then
            CONTAINER_KNOWN="true"
            for count in `seq ${CONTAINER_COUNTS[$container]}|sort -r`
            do
                host=${CONTAINER_HOSTS["$container.$count"]}
                echo ""
                echo "================================================"
                echo "SHUTTING DOWN $container $count IN $host"
                config_file=${container}.${count}.sh
                case "$container" in
                $ES_CONT)
                    if [ "$IGNORE_ES" = "true" ]
                        then
                        echo "Ignoring ES"
                    else
                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/elasticsearch.sh "stop" $count
                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/elasticsearch.sh "delete" $count
                    fi
                ;;
                $KAFKA_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/kafka.sh "stop" $count
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/kafka.sh "delete" $count
                ;;
                $INDEXER_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/config_indexer.sh "stop" $count
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/config_indexer.sh "delete" $count
                ;;
                $VULNERABILITY_INDEXER_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/vulnerability_indexer.sh "stop" $count
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/vulnerability_indexer.sh "delete" $count
                ;;
                $COMPLIANCE_INDEXER_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/compliance_indexer.sh "stop" $count
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/compliance_indexer.sh "delete" $count
                ;;
                $NOTIFICATION_INDEXER_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/notification_indexer.sh "stop" $count
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/notification_indexer.sh "delete" $count
                ;;
                $VULNERABILITY_ANNOTATOR_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/vulnerability_annotator.sh "stop" $count
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/vulnerability_annotator.sh "delete" $count
                ;;
                $SEARCH_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/searchservice.sh "stop" $count
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/searchservice.sh "delete" $count
                ;;
                $TIMEMACHINE_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/timemachine.sh "stop" $count
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/timemachine.sh "delete" $count
                ;;
                $COMPLIANCE_ANNOTATOR_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/compliance_annotator.sh "stop" $count
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/compliance_annotator.sh "delete" $count
                ;;
                $CONFIG_PARSER_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/config_parser.sh "stop" $count
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/config_parser.sh "delete" $count
                ;;
                $USNCRAWLER_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/usncrawler.sh "stop"
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/usncrawler.sh "delete"
                    #$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /bin/rm -r ${USN_CRAWLER_DATA_DIR}
                ;;
                $NOTIFICATION_PROCESSOR_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/notification_processor.sh "stop" $count
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/notification_processor.sh "delete" $count
                ;;
                $PASSWORD_ANNOTATOR_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/password_annotator.sh "stop" $count
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/password_annotator.sh "delete" $count
                ;;
                $CONSUL_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/consul.sh "stop" $count
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/consul.sh "delete" $count
                ;;
                $REGISTRY_UPDATE_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/registry_update.sh "stop" $count
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/registry_update.sh "delete" $count
                    echo "Sleeping for 15 seconds to starve upstreams before performing additional shutdowns"
                    sleep 15
                ;;
                $REGISTRY_MONITOR_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/registry_monitor.sh "stop" $count
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/registry_monitor.sh "delete" $count
                ;;
                $REGCRAWLER)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/service regcrawler "stop"
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/dpkg -r regcrawler
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /bin/rm -r /opt/cloudsight/collector 
                    #$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /bin/rm /var/log/regcrawler.log /var/log/upstart/regcrawler.log
                ;;
                $METRICS_SERVER_CONT)
                    # The container count doesn't really apply here as we want it on every host, so I create my own.
                    # Count through hosts and stop the config and metrics crawler on every host.
                    for host in ${HOSTS[@]}
                        do
                            config_file=${METRICS_SERVER_CONT}.sh
                            $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/metrics_server.sh "stop"
                            $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/metrics_server.sh "delete"
                        done
                ;;
                $CONFIG_AND_METRICS_CRAWLER_CONT)
                    # The container count doesn't really apply here as we want it on every host, so I create my own.
                    # Count through hosts and stop the config and metrics crawler on every host.
                    for host in ${HOSTS[@]}
                        do
                            config_file=${CONFIG_AND_METRICS_CRAWLER_CONT}.sh
                            # To deal with legacy issues
                            $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/service vacrawler "stop"
                            $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/dpkg -r vacrawler
                            $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/service vacrawler-host "stop"
                            $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/dpkg -r vacrawler-host
                            $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/service vacrawler-containers "stop"
                            $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/dpkg -r vacrawler-containers

                            $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo docker stop "config_and_metrics_crawler_1"
                            $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo docker rm "config_and_metrics_crawler_1"

                            $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/config_and_metrics_crawler.sh "stop"
                            $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/config_and_metrics_crawler.sh "delete"
                        done
                ;;
                $MT_LOGSTASH_FORWARDER_CONT)
                    # The container count doesn't really apply here as we want it on every host, so I create my own.
                    # Count through hosts and stop the config and metrics crawler on every host.
                    for host in ${HOSTS[@]}
                        do
                            config_file=${MT_LOGSTASH_FORWARDER_CONT}.sh
                            $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/mt_logstash_forwarder.sh "stop"
                            $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/mt_logstash_forwarder.sh "delete"
                        done
                ;;
                $IMAGE_RESCANNER_CONT)
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/image_rescanner.sh "stop" $count
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/image_rescanner.sh "delete" $count
                ;;
                *)
                    echo "Containers of type $container not yet supported"
                ;;
                esac
            done
        fi
    done

    if [ "$DEPLOY_POLICY" = "shutdown" ]
        then
        echo "All services have been shutdown. End of job."
        exit 0
    fi
fi

if [ "$DEPLOY_POLICY" != "shutdown" ]
    then
    echo "Starting up all specified services."

    #starting up services
    for container in ${CONTAINER_STARTUP_ORDER[@]}
    do
        if [ -z "$CONTAINER_NAME" ] || [ "$CONTAINER_NAME" = $container ]
            then
            for count in `seq ${CONTAINER_COUNTS[$container]}`
            do
                host=${CONTAINER_HOSTS["$container.$count"]}
                echo ""
                echo "================================================"
                echo "STARTING UP $container $count IN $host"
                case "$container" in
                $CONFIG_AND_METRICS_CRAWLER_CONT)
                    for host in ${HOSTS[@]}
                        do

                        config_file=${CONFIG_AND_METRICS_CRAWLER_CONT}.sh

                        #create config file
                        echo "#!/bin/bash" >$config_file
                        echo "CONFIG_AND_METRICS_CRAWLER_IMG=$CONFIG_AND_METRICS_CRAWLER_IMG" >>$config_file
                        echo "CONFIG_AND_METRICS_CRAWLER_CONT=$CONFIG_AND_METRICS_CRAWLER_CONT" >>$config_file
                        echo "CONFIG_AND_METRICS_CRAWLER_NODE_NAME=$host" >>$config_file
                        echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                        echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                        echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                        echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                        echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                        echo "HOST_SUPERVISOR_LOG_DIR=$HOST_SUPERVISOR_LOG_DIR" >>$config_file
                        echo "CONFIG_AND_METRICS_CRAWLER_SPACE_ID=$CONFIG_AND_METRICS_CRAWLER_SPACE_ID" >>$config_file
                        echo "CONFIG_AND_METRICS_CRAWLER_EMIT_URL=$CONFIG_AND_METRICS_CRAWLER_EMIT_URL" >>$config_file
                        echo "CONFIG_AND_METRICS_CRAWLER_ENVIRONMENT=$CONFIG_AND_METRICS_CRAWLER_ENVIRONMENT" >>$config_file
                        echo "CONFIG_AND_METRICS_CRAWLER_FEATURES=$CONFIG_AND_METRICS_CRAWLER_FEATURES" >>$config_file
                        echo "CONFIG_AND_METRICS_CRAWLER_FORMAT=$CONFIG_AND_METRICS_CRAWLER_FORMAT" >>$config_file
                        echo "CONFIG_AND_METRICS_CRAWLER_FREQ=$CONFIG_AND_METRICS_CRAWLER_FREQ"  >>$config_file
                        echo "CONFIG_AND_METRICS_CRAWLER_MODE=$CONFIG_AND_METRICS_CRAWLER_MODE" >>$config_file
                        echo "HOST_CONFIG_AND_METRICS_CRAWLER_SNAPSHOTS_DIR=$HOST_CONFIG_AND_METRICS_CRAWLER_SNAPSHOTS_DIR" >>$config_file
                        echo "CONTAINER_CONFIG_AND_METRICS_CRAWLER_SNAPSHOTS_DIR=$CONTAINER_CONFIG_AND_METRICS_CRAWLER_SNAPSHOTS_DIR" >>$config_file
                        echo "NUM_CORES=$NUM_CORES" >>$config_file

                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                        $SCP startup/config_and_metrics_crawler.sh ${SSH_USER}@$host:config_and_metrics_crawler.sh
                            STAT=$?
                            exit_code=$((exit_code + STAT))

                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv config_and_metrics_crawler.sh $cloudsight_scripts_dir/config_and_metrics_crawler.sh
                            STAT=$?
                            exit_code=$((exit_code + STAT))

                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/config_and_metrics_crawler.sh
                            STAT=$?
                            exit_code=$((exit_code + STAT))

                        $SCP $config_file ${SSH_USER}@$host:$config_file
                            STAT=$?
                            exit_code=$((exit_code + STAT))

                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                            STAT=$?
                            exit_code=$((exit_code + STAT))

                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/config_and_metrics_crawler.sh "start"
                            STAT=$?
                            exit_code=$((exit_code + STAT))

                        if [ $STAT -ne 0 ]
                            then
                            echo "Failed to start $container.$count in $host"
                        fi
                        echo "Config and Metrics Crawler Deployed"
                    done

                ;;
                $METRICS_SERVER_CONT)
                    for host in ${HOSTS[@]}
                        do

                        config_file=${METRICS_SERVER_CONT}.sh

                        #create config file
                        echo "#!/bin/bash" >$config_file
                        echo "METRICS_SERVER_IMG=$METRICS_SERVER_IMG" >>$config_file
                        echo "METRICS_SERVER_CONT=$METRICS_SERVER_CONT" >>$config_file
                        echo "METRICS_SERVER_NODE_NAME=$host" >>$config_file
                        echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                        echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                        echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                        echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                        echo "HOST_CONFIG_AND_METRICS_CRAWLER_SNAPSHOTS_DIR=$HOST_CONFIG_AND_METRICS_CRAWLER_SNAPSHOTS_DIR" >>$config_file
                        echo "CONTAINER_CONFIG_AND_METRICS_CRAWLER_SNAPSHOTS_DIR=$CONTAINER_CONFIG_AND_METRICS_CRAWLER_SNAPSHOTS_DIR" >>$config_file

                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                        $SCP startup/metrics_server.sh ${SSH_USER}@$host:metrics_server.sh
                            STAT=$?
                            exit_code=$((exit_code + STAT))

                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv metrics_server.sh $cloudsight_scripts_dir/metrics_server.sh
                            STAT=$?
                            exit_code=$((exit_code + STAT))

                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/metrics_server.sh
                            STAT=$?
                            exit_code=$((exit_code + STAT))

                        $SCP $config_file ${SSH_USER}@$host:$config_file
                            STAT=$?
                            exit_code=$((exit_code + STAT))

                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                            STAT=$?
                            exit_code=$((exit_code + STAT))

                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/metrics_server.sh "start"
                            STAT=$?
                            exit_code=$((exit_code + STAT))

                        if [ $STAT -ne 0 ]
                            then
                            echo "Failed to start $container.$count in $host"
                        fi
                        echo "Metrics Server Deployed"
                    done
                ;;
                $MT_LOGSTASH_FORWARDER_CONT)
                    for host in ${HOSTS[@]}
                        do

                        config_file=${MT_LOGSTASH_FORWARDER_CONT}.sh

                        #create config file
                        echo "#!/bin/bash" >$config_file
                        echo "MT_LOGSTASH_FORWARDER_IMG=$MT_LOGSTASH_FORWARDER_IMG" >>$config_file
                        echo "MT_LOGSTASH_FORWARDER_CONT=$MT_LOGSTASH_FORWARDER_CONT" >>$config_file
                        echo "MT_LOGSTASH_FORWARDER_NODE_NAME=$host" >>$config_file
                        echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                        echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                        echo "LSF_SPACE_ID=$LSF_TENANT_ID" >> $config_file
                        echo "LSF_SPACE_NAME=$LSF_SPACE_NAME" >> $config_file
                        echo "LSF_PASSWORD=$LSF_PASSWORD" >> $config_file
                        echo "LSF_ORGANISATION=$LSF_ORGANISATION" >> $config_file
                        echo "LSF_TARGET=$LSF_TARGET" >> $config_file

                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                        $SCP startup/mt_logstash_forwarder.sh ${SSH_USER}@$host:mt_logstash_forwarder.sh
                            STAT=$?
                            exit_code=$((exit_code + STAT))
                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv mt_logstash_forwarder.sh $cloudsight_scripts_dir/mt_logstash_forwarder.sh
                            STAT=$?
                            exit_code=$((exit_code + STAT))
                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/mt_logstash_forwarder.sh
                            STAT=$?
                            exit_code=$((exit_code + STAT))
                        $SCP $config_file ${SSH_USER}@$host:$config_file
                            STAT=$?
                            exit_code=$((exit_code + STAT))
                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                            STAT=$?
                            exit_code=$((exit_code + STAT))
                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/mt_logstash_forwarder.sh "start"
                            STAT=$?
                            exit_code=$((exit_code + STAT))

                        STAT=$?
                        if [ $STAT -ne 0 ]
                            then
                            echo "Failed to start $container.$count in $host"
                            exit 1
                        fi
                        echo "Multi Tenant Logstash Forwarder Deployed"
                    done
                ;;
                $ES_CONT)
                    if [ "$IGNORE_ES" = "true" ]
                        then
                        echo "Ignoring ES"
                    else

                        config_file=${ES_CONT}.${count}.sh

                        #create config file
                        echo "#!/bin/bash" >$config_file
                        echo "ES_IMG=$ES_IMG" >>$config_file
                        echo "ES_CONT=$ES_CONT" >>$config_file
                        echo "ES_PORT=$ES_PORT" >>$config_file
                        echo "ES_DATA_VOLUME=$ES_DATA_VOLUME" >>$config_file
                        echo "ES_LOGS_VOLUME=$ES_LOGS_VOLUME" >>$config_file
                        echo "ES_HEAP_SIZE=$ES_HEAP_SIZE" >>$config_file
                        echo "ES_CLUSTER_NAME=cloudsight-es-$ENV" >>$config_file
                        echo "ES_NODE_NAME=$host" >>$config_file
                        echo "ES_PUBLISH_HOST=$host" >>$config_file
                        echo "ES_UNICAST_HOSTS=$ES_HOSTS" >>$config_file
                        echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                        echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                        echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                        echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                        echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                        echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                        echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file

                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p "$ES_DATA_VOLUME"
                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod 755 -R "$ES_DATA_VOLUME"
                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p "$ES_LOGS_VOLUME"
                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod 755 -R "$ES_LOGS_VOLUME"
                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                        $SCP startup/elasticsearch.sh ${SSH_USER}@$host:elasticsearch.sh
                            STAT=$?
                                if [ $STAT -ne 0 ]
                                    then
                                    echo "Failed to start $container.$count in $host"
                                    exit $STAT
                                fi

                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv elasticsearch.sh $cloudsight_scripts_dir/elasticsearch.sh
                            STAT=$?
                                if [ $STAT -ne 0 ]
                                    then
                                    echo "Failed to start $container.$count in $host"
                                    exit $STAT
                                fi

                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/elasticsearch.sh
                            STAT=$?
                                if [ $STAT -ne 0 ]
                                    then
                                    echo "Failed to start $container.$count in $host"
                                    exit $STAT
                                fi

                        $SCP $config_file ${SSH_USER}@$host:$config_file
                            STAT=$?
                                if [ $STAT -ne 0 ]
                                    then
                                    echo "Failed to start $container.$count in $host"
                                    exit $STAT
                                fi

                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                            STAT=$?
                                if [ $STAT -ne 0 ]
                                    then
                                    echo "Failed to start $container.$count in $host"
                                    exit $STAT
                                fi

                        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/elasticsearch.sh "start" $count $host
                            STAT=$?
                                if [ $STAT -ne 0 ]
                                    then
                                    echo "Failed to start $container.$count in $host"
                                    exit $STAT
                                fi

                        echo "Pausing for 15 seconds for elasticsearch startup..."
                        sleep 15
                    fi
                ;;
                $KAFKA_CONT)
                    config_file=${KAFKA_CONT}.${count}.sh

                    #create config file
                    echo "#!/bin/bash" >$config_file
                    echo "KAFKA_IMG=$KAFKA_IMG" >>$config_file
                    echo "KAFKA_CONT=$KAFKA_CONT" >>$config_file
                    echo "KAFKA_HOST=$host" >>$config_file
                    echo "KAFKA_PORT=$KAFKA_PORT" >>$config_file
                    echo "KAFKA_ZOOKEEPER_PORT=$KAFKA_ZOOKEEPER_PORT" >>$config_file
                    echo "KAFKA_JMX_PORT=$KAFKA_JMX_PORT" >>$config_file
                    echo "KAFKA_ZOOKEEPER_JMX_PORT=$KAFKA_ZOOKEEPER_JMX_PORT" >>$config_file
                    echo "KAFKA_DATA_VOLUME=${KAFKA_DATA_VOLUME}_${count}" >>$config_file
                    echo "KAFKA_MAX_MSG_SIZE=$KAFKA_MAX_MSG_SIZE" >>$config_file
                    echo "HOST_KAFKA_ZOOKEEPER_PORT=$((KAFKA_ZOOKEEPER_PORT+count-1))" >>$config_file

                    ZOOKEEPER_CLUSTER=
                    zookeeper_port_offset=0
                    for host in ${KAFKA_CLUSTER[@]} ; do
                       ZOOKEEPER_CLUSTER=${ZOOKEEPER_CLUSTER},${host}:$((KAFKA_ZOOKEEPER_PORT+zookeeper_port_offset))
                        zookeeper_port_offset=$((zookeeper_port_offset+1))
                    done
                    ZOOKEEPER_CLUSTER=${ZOOKEEPER_CLUSTER:1}

                    echo "ZOOKEEPER_CLUSTER=$ZOOKEEPER_CLUSTER" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_KAFKA_LOG_DIR" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                    echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p "$KAFKA_DATA_VOLUME"
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod 755 -R "$KAFKA_DATA_VOLUME"
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config                      
                    $SCP startup/kafka.sh ${SSH_USER}@$host:kafka.sh
                        STAT=$?
                            if [ $STAT -ne 0 ]
                                then
                                echo "Failed to start $container.$count in $host"
                                exit $STAT
                            fi
                            
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv kafka.sh $cloudsight_scripts_dir/kafka.sh
                        STAT=$?
                            if [ $STAT -ne 0 ]
                                then
                                echo "Failed to start $container.$count in $host"
                                exit $STAT
                            fi
                            
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/kafka.sh
                        STAT=$?
                            if [ $STAT -ne 0 ]
                                then
                                echo "Failed to start $container.$count in $host"
                                exit $STAT
                            fi
                            
                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            if [ $STAT -ne 0 ]
                                then
                                echo "Failed to start $container.$count in $host"
                                exit $STAT
                            fi
                            
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            if [ $STAT -ne 0 ]
                                then
                                echo "Failed to start $container.$count in $host"
                                exit $STAT
                            fi
                            
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/kafka.sh "start" $count
                        STAT=$?
                            if [ $STAT -ne 0 ]
                                then
                                echo "Failed to start $container.$count in $host"
                                exit $STAT
                            fi                           

                    echo "Pausing for 15 seconds for kafka startup..."
                    sleep 15
                ;;

                $CONSUL_CONT)
                    #create config file
                    config_file=${CONSUL_CONT}.${count}.sh
                    echo "#!/bin/bash" >$config_file
                    echo "CONSUL_IMG=$CONSUL_IMG" >>$config_file
                    echo "CONSUL_CONT=$CONSUL_CONT" >>$config_file
                    echo "CONSUL_CLUSTER=(${CONSUL_CLUSTER[@]})" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                    echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config           
                    $SCP startup/consul.sh ${SSH_USER}@$host:consul.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv consul.sh $cloudsight_scripts_dir/consul.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/consul.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/consul.sh "start" $count
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi
                ;;

                $INDEXER_CONT)
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$ES_CONT]} $count
                    ES_ENDPOINT=$(eval "echo \$ES$target_node")
                    echo "Connecting to ES $ES_ENDPOINT"
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$KAFKA_CONT]} $count
                    KAFKA_ENDPOINT=$(eval "echo \$KAFKA$target_node")
                    echo "Connecting to KAFKA $KAFKA_ENDPOINT"

                    #create config file
                    config_file=${INDEXER_CONT}.${count}.sh
                    echo "#!/bin/bash" >$config_file
                    echo "INDEXER_IMG=$INDEXER_IMG" >>$config_file
                    echo "INDEXER_CONT=$INDEXER_CONT" >>$config_file
                    echo "KAFKA_HOST=$KAFKA_ENDPOINT" >>$config_file
                    echo "ELASTIC_HOST_1=$ES_ENDPOINT" >>$config_file
                    echo "KAFKA_MAX_MSG_SIZE=$KAFKA_MAX_MSG_SIZE" >>$config_file
                    echo "LS_HEAP_SIZE=$LS_HEAP_SIZE" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                    echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                    $SCP startup/config_indexer.sh ${SSH_USER}@$host:config_indexer.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv config_indexer.sh $cloudsight_scripts_dir/config_indexer.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/config_indexer.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/config_indexer.sh "start" $count
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi
                ;;
                $VULNERABILITY_INDEXER_CONT)
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$ES_CONT]} $count
                    ES_ENDPOINT=$(eval "echo \$ES$target_node")
                    echo "Connecting to ES $ES_ENDPOINT"
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$KAFKA_CONT]} $count
                    KAFKA_ENDPOINT=$(eval "echo \$KAFKA$target_node")
                    echo "Connecting to KAFKA $KAFKA_ENDPOINT"

                    #create config file
                    config_file=${VULNERABILITY_INDEXER_CONT}.${count}.sh
                    echo "#!/bin/bash" >$config_file
                    echo "GENERIC_INDEXER_IMG=$GENERIC_INDEXER_IMG" >>$config_file
                    echo "VULNERABILITY_INDEXER_CONT=$VULNERABILITY_INDEXER_CONT" >>$config_file
                    echo "KAFKA_VULNERABILITY_SCAN_TOPIC=$KAFKA_VULNERABILITY_SCAN_TOPIC" >>$config_file
                    echo "KAFKA_HOST=$KAFKA_ENDPOINT" >>$config_file
                    echo "ELASTIC_HOST_1=$ES_ENDPOINT" >>$config_file
                    echo "KAFKA_MAX_MSG_SIZE=$KAFKA_MAX_MSG_SIZE" >>$config_file
                    echo "LS_HEAP_SIZE=$LS_HEAP_SIZE" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                    echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                    $SCP startup/vulnerability_indexer.sh ${SSH_USER}@$host:vulnerability_indexer.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv vulnerability_indexer.sh $cloudsight_scripts_dir/vulnerability_indexer.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/vulnerability_indexer.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/vulnerability_indexer.sh "start" $count
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi
                ;;
                $COMPLIANCE_INDEXER_CONT)
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$ES_CONT]} $count
                    ES_ENDPOINT=$(eval "echo \$ES$target_node")
                    echo "Connecting to ES $ES_ENDPOINT"
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$KAFKA_CONT]} $count
                    KAFKA_ENDPOINT=$(eval "echo \$KAFKA$target_node")
                    echo "Connecting to KAFKA $KAFKA_ENDPOINT"

                    #create config file
                    config_file=${COMPLIANCE_INDEXER_CONT}.${count}.sh
                    echo "#!/bin/bash" >$config_file
                    echo "GENERIC_INDEXER_IMG=$GENERIC_INDEXER_IMG" >>$config_file
                    echo "COMPLIANCE_INDEXER_CONT=$COMPLIANCE_INDEXER_CONT" >>$config_file
                    echo "KAFKA_COMPLIANCE_TOPIC=$KAFKA_COMPLIANCE_TOPIC" >>$config_file
                    echo "KAFKA_HOST=$KAFKA_ENDPOINT" >>$config_file
                    echo "ELASTIC_HOST_1=$ES_ENDPOINT" >>$config_file
                    echo "KAFKA_MAX_MSG_SIZE=$KAFKA_MAX_MSG_SIZE" >>$config_file
                    echo "LS_HEAP_SIZE=$LS_HEAP_SIZE" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                    echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                    $SCP startup/compliance_indexer.sh ${SSH_USER}@$host:compliance_indexer.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv compliance_indexer.sh $cloudsight_scripts_dir/compliance_indexer.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/compliance_indexer.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/compliance_indexer.sh "start" $count
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi
                ;;
                $NOTIFICATION_INDEXER_CONT)
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$ES_CONT]} $count
                    ES_ENDPOINT=$(eval "echo \$ES$target_node")
                    echo "Connecting to ES $ES_ENDPOINT"
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$KAFKA_CONT]} $count
                    KAFKA_ENDPOINT=$(eval "echo \$KAFKA$target_node")
                    echo "Connecting to KAFKA $KAFKA_ENDPOINT"

                    #create config file
                    config_file=${NOTIFICATION_INDEXER_CONT}.${count}.sh
                    echo "#!/bin/bash" >$config_file
                    echo "NOTIFICATION_INDEXER_IMG=$NOTIFICATION_INDEXER_IMG" >>$config_file
                    echo "NOTIFICATION_INDEXER_CONT=$NOTIFICATION_INDEXER_CONT" >>$config_file
                    echo "KAFKA_HOST=$KAFKA_ENDPOINT" >>$config_file
                    echo "ELASTIC_HOST_1=$ES_ENDPOINT" >>$config_file
                    echo "KAFKA_MAX_MSG_SIZE=$KAFKA_MAX_MSG_SIZE" >>$config_file
                    echo "LS_HEAP_SIZE=$LS_HEAP_SIZE" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                    echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                    $SCP startup/notification_indexer.sh ${SSH_USER}@$host:notification_indexer.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv notification_indexer.sh $cloudsight_scripts_dir/notification_indexer.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/notification_indexer.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/notification_indexer.sh "start" $count
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi
                ;;
                $VULNERABILITY_ANNOTATOR_CONT)
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$ES_CONT]} $count
                    ES_ENDPOINT=$(eval "echo \$ES$target_node")
                    echo "Connecting to ES $ES_ENDPOINT"
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$KAFKA_CONT]} $count
                    KAFKA_ENDPOINT=$(eval "echo \$KAFKA$target_node")
                    echo "Connecting to KAFKA $KAFKA_ENDPOINT"

                    #create config file
                    config_file=${VULNERABILITY_ANNOTATOR_CONT}.${count}.sh
                    echo "#!/bin/bash" >$config_file
                    echo "VULNERABILITY_ANNOTATOR_IMG=$VULNERABILITY_ANNOTATOR_IMG" >>$config_file
                    echo "VULNERABILITY_ANNOTATOR_CONT=$VULNERABILITY_ANNOTATOR_CONT" >>$config_file
                    echo "KAFKA_VULNERABILITY_SCAN_TOPIC=$KAFKA_VULNERABILITY_SCAN_TOPIC" >>$config_file
                    echo "KAFKA_HOST=$KAFKA_ENDPOINT" >>$config_file
                    echo "KAFKA_PORT=$KAFKA_PORT" >>$config_file
                    echo "ELASTIC_HOST_1=$ES_ENDPOINT" >>$config_file
                    echo "ES_PORT=$ES_PORT" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                    echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                    $SCP startup/vulnerability_annotator.sh ${SSH_USER}@$host:vulnerability_annotator.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv vulnerability_annotator.sh $cloudsight_scripts_dir/vulnerability_annotator.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/vulnerability_annotator.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/vulnerability_annotator.sh "start" $count
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi
                ;;
                $SEARCH_CONT)
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$ES_CONT]} $count
                    ES_ENDPOINT=$(eval "echo \$ES$target_node")
                    echo "Connecting to ES $ES_ENDPOINT"
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$KAFKA_CONT]} $count
                    KAFKA_ENDPOINT=$(eval "echo \$KAFKA$target_node")
                    echo "Connecting to KAFKA $KAFKA_ENDPOINT"

                    #create config file
                    config_file=${SEARCH_CONT}.${count}.sh
                    echo "#!/bin/bash" >$config_file
                    echo "SEARCH_IMG=$SEARCH_IMG" >>$config_file
                    echo "SEARCH_CONT=$SEARCH_CONT" >>$config_file
                    echo "ELASTIC_HOST_1=$ES_ENDPOINT" >>$config_file
                    echo "ES_PORT=$ES_PORT" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                    echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                    $SCP startup/searchservice.sh ${SSH_USER}@$host:searchservice.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv searchservice.sh $cloudsight_scripts_dir/searchservice.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/searchservice.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/searchservice.sh "start" $count
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi
                ;;
                $TIMEMACHINE_CONT)
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$ES_CONT]} $count
                    ES_ENDPOINT=$(eval "echo \$ES$target_node")
                    echo "Connecting to ES $ES_ENDPOINT"
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$KAFKA_CONT]} $count
                    KAFKA_ENDPOINT=$(eval "echo \$KAFKA$target_node")
                    echo "Connecting to KAFKA $KAFKA_ENDPOINT"

                    #create config file
                    config_file=${TIMEMACHINE_CONT}.${count}.sh
                    echo "#!/bin/bash" >$config_file
                    echo "TIMEMACHINE_IMG=$TIMEMACHINE_IMG" >>$config_file
                    echo "TIMEMACHINE_CONT=$TIMEMACHINE_CONT" >>$config_file
                    echo "TIMEMACHINE_PORT=$TIMEMACHINE_PORT" >>$config_file
                    echo "KAFKA_HOST=$KAFKA_ENDPOINT" >>$config_file
                    echo "KAFKA_PORT=$KAFKA_PORT" >>$config_file
                    echo "SEARCH_SERVICE=$SEARCH_SERVICE" >> $config_file
                    echo "SEARCH_SERVICE_PORT=$SEARCH_SERVICE_PORT" >> $config_file
                    echo "SEARCH_PORT=$SEARCH_PORT" >> $config_file
                    echo "TIMEMACHINE_PORT=$TIMEMACHINE_PORT" >> $config_file
                    echo "ELASTIC_HOST_1=$ES_ENDPOINT" >>$config_file
                    echo "ES_PORT=$ES_PORT" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                    echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                    $SCP startup/timemachine.sh ${SSH_USER}@$host:timemachine.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv timemachine.sh $cloudsight_scripts_dir/timemachine.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/timemachine.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/timemachine.sh "start" $count
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi
                ;;
                $COMPLIANCE_ANNOTATOR_CONT)
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$ES_CONT]} $count
                    ES_ENDPOINT=$(eval "echo \$ES$target_node")
                    echo "Connecting to ES $ES_ENDPOINT"
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$KAFKA_CONT]} $count
                    KAFKA_ENDPOINT=$(eval "echo \$KAFKA$target_node")
                    echo "Connecting to KAFKA $KAFKA_ENDPOINT"

                    #create config file
                    config_file=${COMPLIANCE_ANNOTATOR_CONT}.${count}.sh
                    echo "#!/bin/bash" >$config_file
                    echo "COMPLIANCE_ANNOTATOR_IMG=$COMPLIANCE_ANNOTATOR_IMG" >>$config_file
                    echo "COMPLIANCE_ANNOTATOR_CONT=$COMPLIANCE_ANNOTATOR_CONT" >>$config_file
                    echo "KAFKA_COMPLIANCE_TOPIC=$KAFKA_COMPLIANCE_TOPIC" >>$config_file
                    echo "KAFKA_HOST=$KAFKA_ENDPOINT" >>$config_file
                    echo "KAFKA_PORT=$KAFKA_PORT" >>$config_file
                    echo "ELASTIC_HOST_1=$ES_ENDPOINT" >>$config_file
                    echo "ES_PORT=$ES_PORT" >>$config_file
                    #echo "COMPLIANCE_UI_PORT=$COMPLIANCE_UI_PORT" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                    echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                    $SCP startup/compliance_annotator.sh ${SSH_USER}@$host:compliance_annotator.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv compliance_annotator.sh $cloudsight_scripts_dir/compliance_annotator.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/compliance_annotator.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/compliance_annotator.sh "start" $count
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi
                ;;
                $CONFIG_PARSER_CONT)
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$KAFKA_CONT]} $count
                    KAFKA_ENDPOINT=$(eval "echo \$KAFKA$target_node")
                    echo "Connecting to KAFKA $KAFKA_ENDPOINT"

                    #create config file
                    config_file=${CONFIG_PARSER_CONT}.${count}.sh
                    echo "#!/bin/bash" >$config_file
                    echo "CONFIG_PARSER_IMG=$CONFIG_PARSER_IMG" >>$config_file
                    echo "CONFIG_PARSER_CONT=$CONFIG_PARSER_CONT" >>$config_file
                    echo "KAFKA_HOST=$KAFKA_ENDPOINT" >>$config_file
                    echo "KAFKA_PORT=$KAFKA_PORT" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                    echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file
                    echo "CONFIG_PARSER_KNOWN_CONFIG_FILES=$CONFIG_PARSER_KNOWN_CONFIG_FILES" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                    $SCP startup/config_parser.sh ${SSH_USER}@$host:config_parser.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv config_parser.sh $cloudsight_scripts_dir/config_parser.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/config_parser.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/config_parser.sh "start" $count
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi
                ;;
                $USNCRAWLER_CONT)
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$ES_CONT]} $count
                    ES_ENDPOINT=$(eval "echo \$ES$target_node")
                    echo "Connecting to ES $ES_ENDPOINT"

                    #create config file
                    config_file=${USNCRAWLER_CONT}.${count}.sh
                    echo "#!/bin/bash" >$config_file
                    echo "USN_CRAWLER_IMG=$USN_CRAWLER_IMG" >>$config_file
                    echo "USNCRAWLER_CONT=$USNCRAWLER_CONT" >>$config_file
                    echo "USN_CRAWLER_SLEEP_TIME=$USN_CRAWLER_SLEEP_TIME" >>$config_file
                    echo "USN_CRAWLER_DATA_DIR=$USN_CRAWLER_DATA_DIR" >>$config_file
                    echo "ELASTIC_HOST_1=$ES_ENDPOINT" >>$config_file
                    echo "ES_PORT=$ES_PORT" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                    echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p ${USN_CRAWLER_DATA_DIR}
                    $SCP ../apps/usncrawler/sec_data/usnrepo.tar ${SSH_USER}@$host:
                    $SCP ../apps/usncrawler/sec_data/data.tar ${SSH_USER}@$host:
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv "usnrepo.tar" ${USN_CRAWLER_DATA_DIR}
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv "data.tar" ${USN_CRAWLER_DATA_DIR}
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host "cd ${USN_CRAWLER_DATA_DIR}; /usr/bin/sudo tar xf usnrepo.tar; /usr/bin/sudo tar xf data.tar"
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP startup/usncrawler.sh ${SSH_USER}@$host:usncrawler.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv usncrawler.sh $cloudsight_scripts_dir/usncrawler.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/usncrawler.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/usncrawler.sh "start"
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi

                    echo "Pausing for USN index initialization"
                    sleep 15
                ;;
                $NOTIFICATION_PROCESSOR_CONT)
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$ES_CONT]} $count
                    ES_ENDPOINT=$(eval "echo \$ES$target_node")
                    echo "Connecting to ES $ES_ENDPOINT"

                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$KAFKA_CONT]} $count
                    KAFKA_ENDPOINT=$(eval "echo \$KAFKA$target_node")
                    echo "Connecting to KAFKA $KAFKA_ENDPOINT"

                    #create config file
                    config_file=${NOTIFICATION_PROCESSOR_CONT}.${count}.sh
                    echo "#!/bin/bash" >$config_file
                    echo "NOTIFICATION_PROCESSOR_IMG=$NOTIFICATION_PROCESSOR_IMG" >>$config_file
                    echo "NOTIFICATION_PROCESSOR_CONT=$NOTIFICATION_PROCESSOR_CONT" >>$config_file
                    echo "ELASTIC_HOST_1=$ES_ENDPOINT" >>$config_file
                    echo "ES_PORT=$ES_PORT" >>$config_file
                    echo "KAFKA_SERVICE=$KAFKA_ENDPOINT:$KAFKA_PORT" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                    echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                    $SCP startup/notification_processor.sh ${SSH_USER}@$host:notification_processor.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv notification_processor.sh $cloudsight_scripts_dir/notification_processor.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/notification_processor.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/notification_processor.sh "start" $count
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi
                ;;
                $PASSWORD_ANNOTATOR_CONT)
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$KAFKA_CONT]} $count
                    KAFKA_ENDPOINT=$(eval "echo \$KAFKA$target_node")
                    echo "Connecting to KAFKA $KAFKA_ENDPOINT"

                    #create config file
                    config_file=${PASSWORD_ANNOTATOR_CONT}.${count}.sh
                    echo "#!/bin/bash" >$config_file
                    echo "PASSWORD_ANNOTATOR_IMG=$PASSWORD_ANNOTATOR_IMG" >>$config_file
                    echo "PASSWORD_ANNOTATOR_CONT=$PASSWORD_ANNOTATOR_CONT" >>$config_file
                    echo "KAFKA_SERVICE=$KAFKA_ENDPOINT:$KAFKA_PORT" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                    $SCP startup/password_annotator.sh ${SSH_USER}@$host:password_annotator.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv password_annotator.sh $cloudsight_scripts_dir/password_annotator.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/password_annotator.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/password_annotator.sh "start" $count
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi
                ;;
                $REGISTRY_UPDATE_CONT)
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$KAFKA_CONT]} $count
                    KAFKA_ENDPOINT=$(eval "echo \$KAFKA$target_node")
                    echo "Connecting to KAFKA $KAFKA_ENDPOINT"

                    #create config file
                    config_file=${REGISTRY_UPDATE_CONT}.${count}.sh
                    echo "#!/bin/bash" >$config_file
                    echo "REGISTRY_UPDATE_IMG=$REGISTRY_UPDATE_IMG" >>$config_file
                    echo "REGISTRY_UPDATE_CONT=$REGISTRY_UPDATE_CONT" >>$config_file
                    echo "CONFIG_TOPIC=$CONFIG_TOPIC" >>$config_file
                    echo "REGISTRY_TOPIC=$REGISTRY_TOPIC" >>$config_file
                    echo "NOTIFICATION_TOPIC=$NOTIFICATION_TOPIC" >>$config_file
                    echo "INSECURE_REGISTRY=$INSECURE_REGISTRY" >>$config_file
                    echo "REGISTRY_UPDATE_IP=$host" >>$config_file
                    echo "REGISTRY_UPDATE_PORT=$REGISTRY_UPDATE_PORT" >>$config_file
                    echo "KAFKA_SERVICE=$KAFKA_ENDPOINT:$KAFKA_PORT" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                    echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                    $SCP startup/registry_update.sh ${SSH_USER}@$host:registry_update.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv registry_update.sh $cloudsight_scripts_dir/registry_update.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/registry_update.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/registry_update.sh "start" $count
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi
                ;;
                $REGISTRY_MONITOR_CONT)
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$KAFKA_CONT]} $count
                    KAFKA_ENDPOINT=$(eval "echo \$KAFKA$target_node")
                    echo "Connecting to KAFKA $KAFKA_ENDPOINT"
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$ES_CONT]} $count
                    ES_ENDPOINT=$(eval "echo \$ES$target_node")
                    echo "Connecting to ES $ES_ENDPOINT"

                    #create config file
                    config_file=${REGISTRY_MONITOR_CONT}.${count}.sh
                    echo "#!/bin/bash" >$config_file
                    echo "REGISTRY_MONITOR_IMG=$REGISTRY_MONITOR_IMG" >>$config_file
                    echo "REGISTRY_MONITOR_CONT=$REGISTRY_MONITOR_CONT" >>$config_file
                    echo "REGCRAWL_HOST_DATA_DIR=$REGCRAWL_HOST_DATA_DIR" >>$config_file
                    echo "REGCRAWL_GUEST_DATA_DIR=$REGCRAWL_GUEST_DATA_DIR" >>$config_file
                    echo "REGISTRY_URL=$CUSTOMER_REGISTRY_PROTOCOL://$CUSTOMER_REGISTRY" >>$config_file
                    echo "ALCHEMY_REGISTRY_URL=$ALCHEMY_REGISTRY_URL" >>$config_file
                    echo "REGISTRY_USER=$REGISTRY_USER" >>$config_file
                    echo "REGISTRY_PASSWORD=$REGISTRY_PW" >>$config_file
                    echo "REGISTRY_EMAIL=$REGISTRY_EMAIL" >>$config_file
                    echo "INSECURE_REGISTRY=$INSECURE_REGISTRY" >>$config_file
                    echo "KAFKA_SERVICE=$KAFKA_ENDPOINT:$KAFKA_PORT" >>$config_file
                    echo "ELASTIC_HOST=$ES_ENDPOINT" >>$config_file
                    echo "ES_PORT=$ES_PORT" >>$config_file
                    echo "REGISTRY_MONITOR_SINGLE_RUN=$REGISTRY_MONITOR_SINGLE_RUN" >>$config_file
                    echo "REGISTRY_ICE_API=$REGISTRY_ICE_API" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                    echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                    $SCP startup/registry_monitor.sh ${SSH_USER}@$host:registry_monitor.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv registry_monitor.sh $cloudsight_scripts_dir/registry_monitor.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/registry_monitor.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/registry_monitor.sh "start" $count
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi
                ;;
                $REGCRAWLER)
                    balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$KAFKA_CONT]} $count
                    KAFKA_ENDPOINT=$(eval "echo \$KAFKA$target_node")
                    echo "Connecting to KAFKA $KAFKA_ENDPOINT"

                    #create config file
                    config_file=${REGCRAWLER}.sh
                    echo "#!/bin/bash" >$config_file
                    echo "REGISTRY_URL=$CUSTOMER_REGISTRY_PROTOCOL://$CUSTOMER_REGISTRY" >>$config_file
                    echo "REGISTRY_USER=$REGISTRY_USER" >>$config_file
                    echo "REGISTRY_PASSWORD=$REGISTRY_PW" >>$config_file
                    echo "REGISTRY_EMAIL=$REGISTRY_EMAIL" >>$config_file
                    echo "INSECURE_REGISTRY=$INSECURE_REGISTRY" >>$config_file
                    echo "REGISTRY_ICE_API=$REGISTRY_ICE_API" >>$config_file
                    echo "INSTANCE_ID=${REGCRAWLER}_${count}" >>$config_file
                    echo "KAFKA_SERVICE=$KAFKA_ENDPOINT:$KAFKA_PORT" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file

                    package=$REGCRAWLER_DEB_FILE

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                    $SCP ../packaging/created_packages/regcrawler/$package ${SSH_USER}@$host:$package
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/apt-get update --fix-missing
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/apt-get install -y --fix-missing  make python2.7 python-pip gcc python-dev rpm uuid
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    echo "installed regcrawler dependencies"
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/dpkg -i $package
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/service regcrawler start
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi
                ;;
                 $IMAGE_RESCANNER_CONT)
                    #balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$ES_CONT]} $count
                    target_node=3
                    ES_ENDPOINT=$(eval "echo \$ES$target_node")
                    echo "Connecting to ES $ES_ENDPOINT"

                    #create config file
                    config_file=${IMAGE_RESCANNER_CONT}.${count}.sh

                    echo "#!/bin/bash" >$config_file
                    echo "IMAGE_RESCANNER_IMG=$IMAGE_RESCANNER_IMG" >>$config_file
                    echo "IMAGE_RESCANNER_CONT=$IMAGE_RESCANNER_CONT" >>$config_file
                    echo "ELASTIC_HOST_1=$ES_ENDPOINT" >>$config_file
                    echo "ES_PORT=$ES_PORT" >>$config_file
                    echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                    echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                    echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                    echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                    echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                    echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                    echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file
                    echo "REGCRAWL1=$REGCRAWL1" >>$config_file
                    echo "REGCRAWL2=$REGCRAWL2" >>$config_file
                    echo "REGCRAWL3=$REGCRAWL3" >>$config_file

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                    $SCP ../kelk-deployment/latest/components/image_rescanner.sh ${SSH_USER}@$host:image_rescanner.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv image_rescanner.sh $cloudsight_scripts_dir/image_rescanner.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/image_rescanner.sh
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SCP $config_file ${SSH_USER}@$host:$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/image_rescanner.sh "start" $count
                        STAT=$?
                            exit_code=$((exit_code + STAT))

                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                    fi
                ;;
                *)
                    echo "Containers of type $container not yet supported"
                ;;
                esac
            done
        fi
    done
fi

echo ""
echo "================================================"

if [ $exit_code -eq 0 ]
    then
    echo "Vulnerability Advisor service deployed - PASS!"
    echo "================================================"
else
    echo "Vulnerability Advisor deploy failed for at least one container - FAIL!"
    echo "Check the logs for more details"
    echo "================================================"
    exit 1
fi

