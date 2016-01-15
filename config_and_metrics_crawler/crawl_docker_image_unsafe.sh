#!/bin/bash

if [ $#  -ne 8 ]; then
        echo 1>&2 "Crawls a docker image. Actually runs a container with it and then crawls it."
        echo 1>&2 "  "
        echo 1>&2 "Usage: $0 <docker_image_id> <URL> <NOTIFICATION_URL>"
        echo 1>&2 "          <container_name> <cs_namespace> <owner_namespace>"
        echo 1>&2 "          <request_id> <instance_id>"
        echo 1>&2 "  i.e.: $0 cloudsight-base kafka://demo3.sl.cloud9.ibm.com:9092/config"
        echo 1>&2 "                           kafka://demo3.sl.cloud9.ibm.com:9092/notification"
        echo 1>&2 "                           container_name_1 registry1/maureen1/ubuntu:latest"
        echo 1>&2 "                           maureen 8a816c56-19bd 8258-06cf8c9b2a69"
        echo 1>&2 "<container_name> will be used to name the temporary container. Make sure it is unique and does not exist already."
        echo 1>&2 "  "
        exit 1
fi

IMAGE=$1
URL=$2
KAFKA_NOTIFICATION_URL=$3
CONTAINER_NAME=`uuid` # XXX creating one anyway
NAMESPACE=$5
OWNER_NAMESPACE=$6
REQUEST_UUID=$7
INSTANCE_ID=$8
FEATURES=os,disk,file,package,config,dockerhistory,dockerinspect

if [ -f ./binaries/sleep ]
then
    BINARIES=`pwd`/binaries
else
    BINARIES="/opt/cloudsight/collector/crawler/binaries"
fi

if [ -f ./kafka-producer.py ]
then
    KAFKA_PRODUCER_PY="kafka-producer.py"
else
    KAFKA_PRODUCER_PY="/opt/cloudsight/collector/crawler/kafka-producer.py"
fi

# Send an empty frame to kafka config so all the other components know that
# something failed.
function send_empty_frame {
    TIMEFORMAT="%Y-%m-%dT%H:%M:%S.%fZ"
    JSON="{'since_timestamp':'0', 'container_long_id':None, \
         'features':'$FEATURES', \
         'timestamp':datetime.datetime.utcnow().strftime('$TIMEFORMAT'), \
         'since':'EPOCH',\
         'compress':False, 'system_type':'container', \
         'container_name':'$CONTAINER_NAME', 'namespace':'$NAMESPACE', \
         'uuid':'$REQUEST_UUID'}"
    python -c "import json; import datetime; print('%s\t%s\t%s') %\
         ('metadata', 'metadata', json.dumps($JSON))" > /tmp/msg
    python ${KAFKA_PRODUCER_PY} /tmp/msg ${URL} config 2>&1 || \
        { echo "$REQUEST_UUID Failed to send an empty frame." ; exit 1; }
}

function send_notification {
    EVENT=$1
    TEXT=$2
    TIMEFORMAT="%Y-%m-%dT%H:%M:%S.%fZ"
    JSON="{'status':'$EVENT', \
         'timestamp':datetime.datetime.utcnow().strftime('$TIMEFORMAT'),\
         'timestamp_ms':int(time.time() * 1e3), 'namespace':'${NAMESPACE}',\
         'uuid':'${REQUEST_UUID}','container_name':'${CONTAINER_NAME}',\
         'processor':'crawler','instance-id':'${INSTANCE_ID}', 'text':'${TEXT}'}"
    python -c "import json; import datetime; import time; print(json.dumps($JSON))" > /tmp/msg
  #  python ${KAFKA_PRODUCER_PY} /tmp/msg ${KAFKA_NOTIFICATION_URL} \
   #     notification 2>&1 || { echo "$REQUEST_UUID Crawler failed to send $EVENT notification." ; exit 1; }
}

docker inspect --format '{{.Id}}' ${IMAGE} 2>&1 >/dev/null
RETVAL=$?
if [ $RETVAL -ne 0 ]
then
        send_notification "start"
        send_notification "error" "The image ${IMAGE} does not exist locally"
        echo "$REQUEST_UUID The image ${IMAGE} does not exist locally."
	exit 1
fi

docker run -d -P --name ${CONTAINER_NAME} ${IMAGE} 2>&1 >/dev/null
RETVAL=$?
# Wait a bit and check if the container crashed
sleep 3
EXIT_CODE=`docker inspect --format '{{.State.ExitCode}}' ${CONTAINER_NAME}`
if [ $RETVAL -ne 0 ] || [ $EXIT_CODE -ne 0 ]
then
        docker rm -f ${CONTAINER_NAME}
	# Instantiate a temporary container for the image
	# The resulting command will be "/bin/sleep 50"
	echo "docker run --name ${CONTAINER_NAME} ${IMAGE}"
	docker run -d -P --entrypoint="/bin/sleep.crawler" -v $BINARIES/sleep:/bin/sleep.crawler \
		--name ${CONTAINER_NAME} ${IMAGE} 2>&1 >/dev/null
fi

CONTAINER_LONG_ID=`docker inspect --format '{{.Id}}' ${CONTAINER_NAME}` 2>&1
# XXX because of issue #278 we can only use short IDs
CONTAINER_ID=`echo $CONTAINER_LONG_ID | cut -c1-12` 2>&1

if [ -z "$CONTAINER_LONG_ID" ]
then
    echo "ERROR: Failed to get CONTAINER_LONG_ID for $IMAGE"
    docker rm -f ${CONTAINER_NAME} 2>&1 >/dev/null
    exit 1
fi

# XXX this is definitely not pretty, but there's no way of
# getting repository information from docker inspect.
# Nor there is a way to get these from inspecting the image.
LONG_IMAGE_NAME=`docker ps --no-trunc | grep ${CONTAINER_NAME} | head -n 1 | awk '{print $2}'` 2>&1
SHORT_IMAGE_NAME=`basename $LONG_IMAGE_NAME` 2>&1
DOCKER_REGISTRY_URL=`dirname $LONG_IMAGE_NAME | awk -F'/' '{print $1}'` 2>&1
IMAGE_TAG=`echo $LONG_IMAGE_NAME | awk -F'\:' '{print $2}'` 2>&1
echo "$REQUEST_UUID Crawling " $CONTAINER_ID $SHORT_IMAGE_NAME, $LONG_IMAGE_NAME, $DOCKER_REGISTRY_URL, $IMAGE_TAG

if [ -z "$LONG_IMAGE_NAME" ]
then
    echo "$REQUEST_UUID ERROR: Failed to get LONG_IMAGE_NAME for $IMAGE"
    docker rm -f ${CONTAINER_NAME} 2>&1 >/dev/null
    exit 1
fi

# logging the notification
send_notification "start"

if [ -f ./crawler.py ]
then
    CRAWLER_PY="crawler.py"
else
    CRAWLER_PY="/opt/cloudsight/collector/crawler/crawler.py"
fi

echo {\"owner_namespace\": \"${OWNER_NAMESPACE}\", \
      \"docker_image_long_name\": \"${LONG_IMAGE_NAME}\", \
      \"docker_image_short_name\": \"${SHORT_IMAGE_NAME}\", \
      \"docker_image_tag\": \"${IMAGE_TAG}\", \
      \"docker_image_registry\": \"${DOCKER_REGISTRY_URL}\", \
      \"uuid\":\"${REQUEST_UUID}\" \
     } > /tmp/crawler_metadata.json

echo "$REQUEST_UUID Running ${CRAWLER_PY}"

printf "$REQUEST_UUID "
/usr/bin/python ${CRAWLER_PY} --crawlmode OUTCONTAINER --crawlContainers $CONTAINER_ID \
    --url $URL --since EPOCH \
    --features $FEATURES --numprocesses 1 \
    --extraMetadataFile /tmp/crawler_metadata.json \
    --frequency -1 --compress true --options "{\"connection\": {}, \
	\"file\": {\"exclude_dirs\": [\"boot\", \"dev\", \"proc\", \
	\"sys\", \"mnt\", \"tmp\", \"var/cache\", \"usr/share/man\", \
	\"usr/share/doc\", \"usr/share/mime\"], \"root_dir\": \"/\"}, \
	\"package\": {}, \"process\": {}, \"config\": {\"exclude_dirs\": \
	[\"dev\", \"proc\", \"mnt\", \"tmp\", \"var/cache\", \"usr/share/man\",\
	 \"usr/share/doc\", \"usr/share/mime\"], \"known_config_files\": \
	[\"etc/login.defs\",\"etc/passwd\", \"etc/hosts\", \"etc/mtab\", \
	\"etc/group\", \"vagrant/vagrantfile\", \"vagrant/Vagrantfile\", \
	\"etc/motd\",\"etc/login.defs\",\"etc/shadow\",\"etc/login.defs\", \
	\"etc/shadow\",\"etc/pam.d/system-auth\",\"etc/pam.d/common-password\", \
	\"etc/pam.d/password-auth\",\"etc/pam.d/system-auth\",\"etc/pam.d/other\", \
	\"etc/pam.d/common-auth\",\"etc/pam.d/common-account\", \
	\"etc/pam.d/password-auth\",\"etc/pam.d/system-auth\", \
	\"etc/pam.d/common-password\",\"etc/pam.d/password-auth\", \
	\"etc/pam.d/system-auth\",\"etc/pam.d/common-auth\", \
	\"etc/pam.d/common-account\",\"etc/cron.daily/logrotate\", \
	\"etc/logrotate.conf\",\"etc/logrotate.d/*\",\"etc/sysctl.conf\", \
	\"etc/rsyslog.conf\",\"etc/ssh/sshd_config\",\"etc/hosts.allow\", \
	\"etc/hosts.deny\",\"etc/hosts.equiv\",\"etc/pam.d/rlogin\", \
	\"etc/pam.d/rsh\",\"etc/pam.d/rexec\",\"etc/snmpd.conf\", \
	\"etc/snmp/snmpd.conf\",\"etc/snmp/snmpd.local.conf\", \
	\"usr/local/etc/snmp/snmpd.conf\",\"usr/local/etc/snmp/snmpd.local.conf\" \
	,\"usr/local/share/snmp/snmpd.conf\",\"usr/local/share/snmp/snmpd.local.conf\" \
	,\"usr/local/lib/snmp/snmpd.conf\",\"usr/local/lib/snmp/snmpd.local.conf\", \
	\"usr/share/snmp/snmpd.conf\",\"usr/share/snmp/snmpd.local.conf\", \
	\"usr/lib/snmp/snmpd.conf\",\"usr/lib/snmp/snmpd.local.conf\", \
	\"etc/hosts\",\"etc/hostname\", \"etc/mtab\", \
	\"usr/lib64/snmp/snmpd.conf\",\"usr/lib64/snmp/snmpd.local.conf\", \
	\"etc/supervisor/conf.d/supervisord.conf\",\"/usr/bin/start.sh\", \
	\"etc/services\", \"etc/init/ssh.conf\"], \
	\"discover_config_files\": false, \"root_dir\": \"/\"}, \"metric\": {}, \
	\"disk\": {}, \"os\": {}, \
	\"metadata\": {\"container_long_id_to_namespace_map\": {\"${CONTAINER_LONG_ID}\": \"${NAMESPACE}\"}}}" 2>&1 \
        && echo "Successfully crawled and frame emitted."

RETVAL=$?
[ $RETVAL -eq 0 ] && STATUS="completed"
[ $RETVAL -ne 0 ] && STATUS="error"

echo "$REQUEST_UUID Removing container $CONTAINER_NAME"
docker rm -f ${CONTAINER_NAME} 2>&1 >/dev/null

# logging the notification
send_notification ${STATUS} "The return code of crawler.py was $RETVAL"

exit $RETVAL
