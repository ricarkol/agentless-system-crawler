#!/bin/bash
for i in `docker ps -a | grep cloudsight-password-annotator | cut -d' ' -f1`
do
    docker rm -f $i
done

docker run  --name cloudsight-password-annotator -d cloudsight/password-annotator --kafka-url csdev.sl.cloud9.ibm.com:9092 --receive-topic config --annotation-topic compliance --notification-topic notification --instance-id password-annotator_1

