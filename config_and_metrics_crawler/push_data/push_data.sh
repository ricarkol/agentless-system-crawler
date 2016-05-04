#!/bin/bash

SIMULATE="0"
space="0"
# sleep seconds
ANNOUNCEMENT_SLEEP=3
EXECUTE_SLEEP=3

function opening_banner()
{
    echo "----------------------------------------------------------------------------------"
    echo ""
    # banner "Push Data"
    echo " PUSH DATA: Pushes a given feature file to kafka,"
    echo ""
    echo "----------------------------------------------------------------------------------"
}

function announcement()
{
    if [ $space = "1" ]; then
	echo "             $*  "
    else
	echo ""
	echo "====>  #####  $*  ####"
	echo ""
    fi
    sleep $ANNOUNCEMENT_SLEEP
    space="0"
}

function execute_cmd()
{
    if [[ "$SIMULATE" = "1" ]]; then
	echo "SIMULATE: $*"
    else
	echo "               $*"
	$*
    fi
    sleep $EXECUTE_SLEEP
}

# metadata file variables
#{"since_timestamp": 0, 
#    "container_long_id": "70b3e325d4e276ab0443d42c4bacaa722288d55230928429d6bbb09bd96e7b2f", "features": "package,config", "timestamp": "2015-12-01T14:09:33-0600", "docker_image_short_name": "precise_40", "since": "EPOCH", "compress": false, "docker_image_registry": "openstack_glance_precise_40", "owner_namespace": "cloudsight", "docker_image_tag": "va4vmtest", "system_type": "container", "container_name": "vm_name_70b3e325d4e276ab0443d42c4bacaa72", "container_image": "precise_40", "docker_image_long_name": "openstack_glance_precise_40", "namespace": "openstack_glance_precise_40", "uuid": "70b3e325d4e276ab0443d42c4bacaa722288d55230928429d6bbb09bd96e7b2f"}

CONTAINER_NAME="whs_vm"
CONTAINER_ID="whs_vm_id"
FEATURES="os,package,config,file"
DOCKER_IMAGE_NAME="whs_vm_image"
DOCKER_IMAGE_REGISTRY="whs_vm_registry"
DOCKER_IMAGE_TAG="whs4testing"
NAMESPACE="WatsonHealthServices_T1"
UUID="q1w2e3r4t5y6u7i8"

# generates metadata file with all required data
# to push into the r2d2.
function generate_data_file()
{
    image_no=$1
    uuid_postfix=$2
    featurefile=$3
    datafile=$4

    CONTAINER_NAME="${CONTAINER_NAME}_${image_no}"
    CONTAINER_ID="${CONTAINER_ID}_${image_no}"
    DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME}_${image_no}"
    DOCKER_IMAGE_REGISTRY="whs_vm_registry"
    DOCKER_IMAGE_TAG="whs4testing"
    if [ "X${uuid_postfix}" != "X" ]; then
	UUID="${UUID}_${uuid_postfix}"    
    fi

    announcement "Generating the data file... "
    
    echo -e "metadata\t\"metadata\"\t{\"since_timestamp\": 0, \"container_long_id\": \"$CONTAINER_ID\", \"features\": \"$FEATURES\", \"timestamp\": \"2015-12-01T14:09:33-0600\", \"docker_image_short_name\": \"$DOCKER_IMAGE_NAME\", \"since\": \"EPOCH\", \"compress\": false, \"docker_image_registry\": \"$DOCKER_IMAGE_REGISTRY\", \"owner_namespace\": \"cloudsight\", \"docker_image_tag\": \"$DOCKER_IMAGE_TAG\", \"system_type\": \"container\", \"container_name\": \"$CONTAINER_NAME\", \"container_image\": \"$DOCKER_IMAGE_NAME\", \"docker_image_long_name\": \"$DOCKER_IMAGE_NAME\", \"namespace\": \"$NAMESPACE\", \"uuid\": \"$UUID\"}" > $datafile

    announcement "Appending the data to generate the data file... "

    cat $featurefile >> $datafile
}


function push_data_to_kafka()
{
    cs_rootdir=$1
    datafile=$2
    kafka_node=$3
    kafka_port=$4

    announcement "Pushing the data to kafka ..."

    cd ${cs_rootdir}/collector/crawler

    execute_cmd sudo python kafka-producer.py ${cs_rootdir}/collector/crawler/push_data/$datafile kafka://$kafka_node:$kafka_port/config
}


#################################################################################
#     Start of the Main program
#################################################################################

opening_banner

if [ $# -lt 10 ]; then
    echo "Usage:  $0 "
    echo "           -c <cloudsight_rootdir> "
    echo "           -n <image_number>    [to be used in constructing metadata] "
    echo "           -N <name_space>      [to be used in constructing metadata] "
    echo "           -f <feature_file> "    
    echo "           -k <kafka_url>        : example: 'r2d2.sl.cloud9.ibm.com' "    
    echo "           [ -p <kafka_port> ]   : default is 9092"        
    echo "           [ -u <uuid_postfix> ] : default is Null, which means default UUID is: 'q1w2e3r4t5y6u7i8'"
    echo ""
    exit 1
fi

cloudsight_rootdir=""
image_number="1"
feature_file="test1.0"
kafka_node="r2d2.sl.cloud9.ibm.com"
kafka_port="9092"
uuid_postfix=""

while getopts ":c:n:N:f:k:p:u:" optname; do
    case "$optname" in
	"c")
	    cloudsight_rootdir=$OPTARG
	    echo "Cloudsight RootDir: $cloudsight_rootdir"
	    ;;
	"n")
	    image_number=$OPTARG
	    echo "Image No: $image_number"
	    ;;
	"N")
	    NAMESPACE=$OPTARG
	    echo "Name Space: $NAMESPACE"
	    ;;
	"f")
	    feature_file=$OPTARG
	    echo "Feature Filename: $feature_file"
	    ;;
	"k")
	    kafka_node=$OPTARG
	    echo "Kafka Node: $kafka_node"
	    ;;
	"p")
	    kafka_port=$OPTARG
	    echo "Kafka Port: $kafka_port"
	    ;;
	"u")
	    uuid_postfix=$OPTARG
	    echo "UUID Postfix: $uuid_postfix"
	    ;;
	"?")
	    echo "Unknown option $OPTARG, skipping... "
	    exit 1
	    ;;
    esac
done

data_file="data_${feature_file}_img${image_number}"

generate_data_file $image_number $uuid_postfix $feature_file $data_file

push_data_to_kafka $cloudsight_rootdir $data_file $kafka_node $kafka_port

echo ""
echo " Done."
echo "----------------------------------------------------------------------------------"


