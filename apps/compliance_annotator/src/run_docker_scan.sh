#!/bin/bash
for i in `docker ps -a | grep kafka_vulnerability_annotator | cut -d' ' -f1`
do
    docker rm -f $i
done

docker run  --name kafka_vulnerability_annotator -d kafka_vulnerability_annotator --kafka-url kafka-cs.sl.cloud9.ibm.com:9092 --receive-topic config --annotation-topic vulnerabilityscan --notification-topic notification

