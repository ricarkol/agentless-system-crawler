#!/bin/bash
#
# Vulnerability Advisor deployment orchestrator
# (c) IBM Research 2015
#

if [ $# -ne 3 ] ; then
   echo "Usage: $0 <ENV> <IMAGE_TAG> <HOST>"
   exit 1
fi


ENV=$1
IMAGE_TAG=$2
host=$3

echo "Deploying to ENV ${ENV}"
echo "BOOTSTRAP: ${BOOTSTRAP}"
echo "IMAGE_TAG: $IMAGE_TAG"

. ../config/hosts.${ENV}
. ../config/docker-images

SCP="scp -o StrictHostKeyChecking=no"
SSH="ssh -o StrictHostKeyChecking=no"


cloudsight_scripts_dir="/opt/cloudsight/kafka-elk-cloudsight"
. ../config/component_configs.sh

KAFKA_ENDPOINT=$(eval "echo \$KAFKA$target_node")
echo "Connecting to KAFKA $KAFKA_ENDPOINT"

#create config file
cloudsight_scripts_dir="/opt/cloudsight/kafka-elk-cloudsight"
config_file=single_run_registry_monitor.sh
echo "#!/bin/bash" >$config_file
echo "REGISTRY_MONITOR_IMG=$REGISTRY_MONITOR_IMG" >>$config_file
echo "REGISTRY_MONITOR_CONT=$REGISTRY_MONITOR_CONT" >>$config_file
echo "REGCRAWL_HOST_DATA_DIR=$REGCRAWL_HOST_DATA_DIR" >>$config_file
echo "REGCRAWL_GUEST_DATA_DIR=$REGCRAWL_GUEST_DATA_DIR" >>$config_file
echo "REGISTRY_URL=$CUSTOMER_REGISTRY_PROTOCOL://$CUSTOMER_REGISTRY" >>$config_file
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
$SCP startup/single_run_registry_monitor.sh ${SSH_USER}@$host:single_run_registry_monitor.sh
$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv single_run_registry_monitor.sh $cloudsight_scripts_dir/single_run_registry_monitor.sh
$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo chmod u+x $cloudsight_scripts_dir/single_run_registry_monitor.sh
$SCP $config_file ${SSH_USER}@$host:$config_file
$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo CONFIG_FILE=$cloudsight_scripts_dir/config/$config_file $cloudsight_scripts_dir/single_run_registry_monitor.sh 

# run the recalculate job @ 2.00 AM on Saturday localtime
echo "00 02 * * 6 root ${cloudsight_scripts_dir}/single_run_registry_monitor.sh" > recalculate
$SCP recalculate ${SSH_USER}@$host:/etc/cron.d/recalculate 
