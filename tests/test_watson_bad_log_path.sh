#!/bin/bash


if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# one of the log files specified in the /etc/logfiles
# is not absolute path, but the other one is.
# The crawler links files with absolute paths only
# /var/log/crawler_container_logs/<watson-prefix>.<container-short-id>/docker.log
# Returns 1 if success, 0 otherwise

NAME=test_watson_bad_log_path
HOST_NAMESPACE=dev-test
# Cleanup
rm -rf /var/log/crawler_container_logs/watson_test.service_1.service_v003.*/
rm -f /tmp/$NAME.log /tmp/$NAME-0.log /tmp/$NAME-1.log /tmp/$NAME-2.log
docker rm -f $NAME 2> /dev/null > /dev/null

timeout 10 python2.7 ../config_and_metrics_crawler/crawler.py --crawlmode OUTCONTAINER \
	--features=nofeatures --url file:///tmp/`uuid` \
    --environment watson \
	--linkContainerLogFiles --numprocesses 1 \
	--url file:///tmp/$NAME --format graphite --namespace ${HOST_NAMESPACE} --logfile /tmp/$NAME.log& #2>/dev/null &
PID=$!

MSG=`uuid`
# /var/log/messages is linked by default. Here we test that adding it again won't do any harm.
docker run -d --name $NAME ubuntu bash -c "\
    echo CLOUD_APP_GROUP=\'watson_test\' >>/etc/csf_env.properties; \
    echo CLOUD_APP=\'service_1\' >>/etc/csf_env.properties; \
    echo CLOUD_TENANT=\'public\' >>/etc/csf_env.properties; \
    echo CLOUD_AUTO_SCALE_GROUP=\'service_v003\' >>/etc/csf_env.properties; \
    echo CRAWLER_METRIC_PREFIX=watson_test.service_1.service_v003  >>/etc/csf_env.properties; \
    echo /var/log/../log/test1.log >> /etc/logfiles;\
    echo /var/log/test2.log >> /etc/logfiles;\
    echo $MSG > /var/log/test1.log; \
    echo $MSG > /var/log/test2.log; \
    sleep 6000" 2> /dev/null > /dev/null

ID1=`docker ps | grep $NAME | awk '{print $1}'`

sleep 2

# By now the log should be there
test_log_fc=`find /var/log/crawler_container_logs/${HOST_NAMESPACE}.watson_test.service_1.service_v003.$ID1/* | grep -c "test..log"`
log_msg_cnt=`grep "User provided a log file path that is not absolute" /tmp/watson_test*.log | wc -l `
if [ $test_log_fc == 1 ] && [ $log_msg_cnt == 2 ] ;
then
    echo 1;
else
    echo 0
fi

docker rm -f $NAME > /dev/null
