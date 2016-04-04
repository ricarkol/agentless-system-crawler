#!/bin/bash


#
# Vulnerability Advisor deployment orchestrator
# (c) IBM Research 2015
#

if [ $# -ne 2 ] ; then
   echo "Usage: $0 <ENV>  <IMAGE_TAG>"
   exit 1
fi


ENV=$1
IMAGE_TAG=$2

echo "Deploying to ENV ${ENV}"
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
    for count in 1
    do
        host=${CONTAINER_HOSTS["$container.$count"]}
        config_file=${container}.${count}.sh
        case "$container" in
        $USNCRAWLER_CONT)
            echo "SHUTTING DOWN $container $count IN $host"
            $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/usncrawler.sh "stop"
            $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/usncrawler.sh "delete"
            #$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /bin/rm -r ${USN_CRAWLER_DATA_DIR}
        ;;
        *)
            echo  -n
        ;;
        esac
    done
done

#starting up services
for container in ${CONTAINER_STARTUP_ORDER[@]}
do
    for count in 1
    do
        host=${CONTAINER_HOSTS["$container.$count"]}
        case "$container" in
        $USNCRAWLER_CONT)
            echo "STARTING UP $container $count IN $host"
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
        *)
            echo  -n
        ;;
        esac
    done
done

if [ "$?" -eq "0" ]
    then
    echo "usncrawler service deployed!" 
else
    echo "usncrawler deployment failed!"
    exit 1
fi

