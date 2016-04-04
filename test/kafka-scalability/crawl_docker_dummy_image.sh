#!/bin/bash

if [ $#  -ne 8 ]; then
        echo 1>&2 "Sends a dummy frame file to kafka. Used in VA for scalability tests."
        echo 1>&2 "  "
        echo 1>&2 "Usage: $0 <dummy_frame_file> <URL> <NOTIFICATION_URL>"
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

DUMMY_FRAME_FILE=$1
URL=$2
KAFKA_NOTIFICATION_URL=$3
CONTAINER_NAME=`uuid` # XXX creating one anyway
NAMESPACE=$5
OWNER_NAMESPACE=$6
REQUEST_UUID=$7
INSTANCE_ID=$8

if [ -f ../../collector/crawler/kafka-producer.py ]
then
    KAFKA_PRODUCER_PY="../../collector/crawler/kafka-producer.py"
else
    KAFKA_PRODUCER_PY="/opt/cloudsight/collector/crawler/kafka-producer.py"
fi

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
    python ${KAFKA_PRODUCER_PY} /tmp/msg ${KAFKA_NOTIFICATION_URL} \
        notification 2>&1 || { echo "$REQUEST_UUID Crawler failed to send $EVENT notification." ; exit 1; }
}

function send_dummy_frame {
    DUMMY_FRAME_FILE=$1
    python ${KAFKA_PRODUCER_PY} ${DUMMY_FRAME_FILE} ${URL} \
        notification 2>&1 || { echo "$REQUEST_UUID Crawler failed to send $EVENT notification." ; exit 1; }
}

# logging the notification
send_notification "start"

send_dummy_frame ${DUMMY_FRAME_FILE}

# logging the notification
send_notification "completed" "The return code of crawler.py was success"

exit $RETVAL
