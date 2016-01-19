#!/bin/bash


#
# Vulnerability Advisor deployment orchestrator
# (c) IBM Research 2015
#

if [ $# -eq 4 ]
    then
    echo "Processing all containers"
    IGNORE_ES=false
    CONTAINER_NAME=
elif [ $# -eq 5 ]
    then
    if [ "$5" = "true" ]
       then
        echo "Processing all containers except ES"
        IGNORE_ES=true
        CONTAINER_NAME=
    elif [ "$5" = "false" ]
        then
        echo "Processing all containers"
        IGNORE_ES=false
        CONTAINER_NAME=
    else
        echo "Processing container:" $5
        IGNORE_ES=false
        CONTAINER_NAME=cloudsight-$5
    fi
else
   echo "Usage: $0 <ENV> <BOOTSTRAP> <IMAGE_TAG> <SHUTDOWN> [<IGNORE_ES> | <CONTAINER_NAME>]"
   exit 1
fi


ENV=$1
BOOTSTRAP=$2
IMAGE_TAG=$3
SHUTDOWN=$4

echo "Deploying to ENV ${ENV}"
echo "BOOTSTRAP: ${BOOTSTRAP}"
echo "IMAGE_TAG: $IMAGE_TAG"

. ../config/hosts.${ENV}
. ../config/docker-images

SCP="scp -o StrictHostKeyChecking=no"
SSH="ssh -o StrictHostKeyChecking=no"

if [ "$BOOTSTRAP" = "true" ]
    then
    . utils/bootstrap_hosts.sh
fi

. ../config/container_hosts.${ENV}

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
    if [ "$num_nodes" -eq "0" ] 
        then
        target_node=1
    else
        if [ "$client_num" -gt "$num_nodes" ]
            then
            client_num=$(($client_num % $num_nodes))
        fi

        target_node=$(((($num_nodes - $client_num) % $num_nodes) + 1))

        if [ "$target_node" -eq "0" ] 
            then
            target_node=$num_nodes
        fi
    fi
    echo "Target node is $target_node"
    return 0
    }

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
#                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/compliance_indexer.sh "stop" $count
#                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/compliance_indexer.sh "delete" $count
            ;;
            $REGISTRY_UPDATE_CONT)
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/registry_update.sh "stop" $count
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/registry_update.sh "delete" $count
                #starve upstreams before additional shutdowns
                sleep 60
            ;;
            $REGISTRY_MONITOR_CONT)
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/registry_monitor.sh "stop" $count
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/registry_monitor.sh "delete" $count
                #$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /bin/rm -r $REGCRAWL_HOST_DATA_DIR
                #starve upstreams before additional shutdowns
                sleep 60
            ;;
            $REGCRAWLER)
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/service regcrawler "stop"
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/dpkg -r regcrawler
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /bin/rm -r /opt/cloudsight/collector 
                #$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /bin/rm /var/log/regcrawler.log /var/log/upstart/regcrawler.log
            ;;
            *)
                echo "Containers of type $container not yet supported"
            ;;
            esac
        done
    fi
done

if [ -z "$CONTAINER_KNOWN" ]
    then
    echo "Containers of type $CONTAINER_NAME unknown"
    exit 1
fi

if [ "$SHUTDOWN" = "true" ]
    then
    echo "All services have been shutdown. End of job."
    exit 0
fi

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
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv elasticsearch.sh $cloudsight_scripts_dir/elasticsearch.sh
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/elasticsearch.sh
                    $SCP $config_file ${SSH_USER}@$host:$config_file
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                    $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/elasticsearch.sh "start" $count $host

                    STAT=$?
                    if [ $STAT -ne 0 ]
                        then
                        echo "Failed to start $container.$count in $host"
                        exit 1
                    fi
                    echo "Pausing for elasticsearch startup..."
                    sleep 60
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
                echo "KAFKA_ZOO_KEEPER_PORT=$KAFKA_ZOO_KEEPER_PORT" >>$config_file
                echo "KAFKA_DATA_VOLUME=$KAFKA_DATA_VOLUME" >>$config_file
                echo "KAFKA_MAX_MSG_SIZE=$KAFKA_MAX_MSG_SIZE" >>$config_file
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
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv kafka.sh $cloudsight_scripts_dir/kafka.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/kafka.sh
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/kafka.sh "start" $count

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
                fi

                echo "Pausing for kafka startup..."
                sleep 30
            ;;

            $CONSUL_CONT)
                #create config file
                config_file=${CONSUL_CONT}.${count}.sh
                echo "#!/bin/bash" >$config_file
                echo "CONSUL_IMG=$CONSUL_IMG" >>$config_file
                echo "CONSUL_CONT=$CONSUL_CONT" >>$config_file
                echo "HOSTS_containers_consul=$CONSUL1 $CONSUL2 $CONSUL3" >>$config_file
                echo "IMAGE_TAG=$IMAGE_TAG" >>$config_file
                echo "REGISTRY=$DEPLOYMENT_REGISTRY" >>$config_file
                echo "CONTAINER_SUPERVISOR_LOG_DIR=$CONTAINER_SUPERVISOR_LOG_DIR" >>$config_file
                echo "CONTAINER_CLOUDSIGHT_LOG_DIR=$CONTAINER_CLOUDSIGHT_LOG_DIR" >>$config_file
                echo "HOST_CONTAINER_LOG_DIR=$HOST_CONTAINER_LOG_DIR" >>$config_file
                echo "CLOUDSIGHT_DIR=$CLOUDSIGHT_DIR" >>$config_file
                echo "SUPERVISOR_DIR=$SUPERVISOR_DIR" >>$config_file

                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
                $SCP startup/consul.sh ${SSH_USER}@$host:consul.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv consul.sh $cloudsight_scripts_dir/consul.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/consul.sh
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/consul.sh "start" $count

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
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
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv config_indexer.sh $cloudsight_scripts_dir/config_indexer.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/config_indexer.sh
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/config_indexer.sh "start" $count

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
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
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv vulnerability_indexer.sh $cloudsight_scripts_dir/vulnerability_indexer.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/vulnerability_indexer.sh
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/vulnerability_indexer.sh "start" $count

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
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
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv compliance_indexer.sh $cloudsight_scripts_dir/compliance_indexer.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/compliance_indexer.sh
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/compliance_indexer.sh "start" $count

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
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
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv notification_indexer.sh $cloudsight_scripts_dir/notification_indexer.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/notification_indexer.sh
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/notification_indexer.sh "start" $count

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
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
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv vulnerability_annotator.sh $cloudsight_scripts_dir/vulnerability_annotator.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/vulnerability_annotator.sh
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/vulnerability_annotator.sh "start" $count

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
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
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv searchservice.sh $cloudsight_scripts_dir/searchservice.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/searchservice.sh
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/searchservice.sh "start" $count

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
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
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv timemachine.sh $cloudsight_scripts_dir/timemachine.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/timemachine.sh
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/timemachine.sh "start" $count

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
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
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv compliance_annotator.sh $cloudsight_scripts_dir/compliance_annotator.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/compliance_annotator.sh
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/compliance_annotator.sh "start" $count

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
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
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv config_parser.sh $cloudsight_scripts_dir/config_parser.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/config_parser.sh
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/config_parser.sh "start" $count

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
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
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv "data.tar" ${USN_CRAWLER_DATA_DIR}
                $SSH ${SSH_USER}@$host HOST=$host "cd ${USN_CRAWLER_DATA_DIR}; /usr/bin/sudo tar xf usnrepo.tar; /usr/bin/sudo tar xf data.tar"

                $SCP startup/usncrawler.sh ${SSH_USER}@$host:usncrawler.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv usncrawler.sh $cloudsight_scripts_dir/usncrawler.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/usncrawler.sh
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/usncrawler.sh "start"

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
                fi

                echo "Pausing for USN index initialization"
                sleep 30
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
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv notification_processor.sh $cloudsight_scripts_dir/notification_processor.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/notification_processor.sh
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/notification_processor.sh "start" $count

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
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
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv password_annotator.sh $cloudsight_scripts_dir/password_annotator.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/password_annotator.sh
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/password_annotator.sh "start" $count

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
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
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv registry_update.sh $cloudsight_scripts_dir/registry_update.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/registry_update.sh
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/registry_update.sh "start" $count

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
                fi
            ;;
            $REGISTRY_MONITOR_CONT)
                balanced_cluster_node ${WRITABLE_CLUSTER_NODES[$KAFKA_CONT]} $count
                KAFKA_ENDPOINT=$(eval "echo \$KAFKA$target_node")
                echo "Connecting to KAFKA $KAFKA_ENDPOINT"

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
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv registry_monitor.sh $cloudsight_scripts_dir/registry_monitor.sh
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/registry_monitor.sh
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/registry_monitor.sh "start" $count

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
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
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/apt-get update --fix-missing
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/apt-get install -y --fix-missing  make python2.7 python-pip gcc python-dev rpm uuid
                echo "installed regcrawler dependencies"
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/dpkg -i $package
                $SCP $config_file ${SSH_USER}@$host:$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
                $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/service regcrawler start

                STAT=$?
                if [ $STAT -ne 0 ]
                    then
                    echo "Failed to start $container.$count in $host"
                    exit 1
                fi
            ;;
            *)
                echo "Containers of type $container not yet supported"
            ;;
            esac
        done
    fi
done

if [ "$?" -eq "0" ]
    then
    echo "Vulnerability Advisor service deployed!" 
else
    echo "Vulnerability Advisor deployment failed!"
    exit 1
fi

