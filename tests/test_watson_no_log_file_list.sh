#!/bin/bash


if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# since no files are listed in /etc/logfiles no links are created
# /var/log/crawler_container_logs/<watson-prefix>.<container-short-id>/docker.log
# Returns 1 if success, 0 otherwise

NAME=test_watson_no_log_file_list
# Cleanup
rm -rf /var/log/crawler_container_logs/watson_test.service_1.service_v003.*/
docker rm -f $NAME 2> /dev/null > /dev/null

timeout 10 python2.7 ../config_and_metrics_crawler/crawler.py --crawlmode OUTCONTAINER \
	--features=nofeatures --url file:///tmp/`uuid` \
    --environment watson \
	--linkContainerLogFiles --frequency 1 --numprocesses 1 \
	--url file:///tmp/$NAME --format graphite & #2>/dev/null &
PID=$!

MSG=`uuid`
# /var/log/messages is linked by default. Here we test that adding it again won't do any harm.
docker run -d --name $NAME ubuntu bash -c "\
    echo CLOUD_APP_GROUP=\'watson_test\' >>/etc/csf_env.properties; \
    echo CLOUD_APP=\'service_1\' >>/etc/csf_env.properties; \
    echo CLOUD_TENANT=\'public\' >>/etc/csf_env.properties; \
    echo CLOUD_AUTO_SCALE_GROUP=\'service_v003\' >>/etc/csf_env.properties; \
    echo CRAWLER_METRIC_PREFIX=#CLOUD_APP_GROUP:#CLOUD_APP:#CLOUD_AUTO_SCALE_GROUP | sed 's/#/\$/g'  >>/etc/csf_env.properties; \
    echo $MSG > /var/log/test1.log; \
    echo $MSG > /var/log/test2.log; \
    sleep 6000" 2> /dev/null > /dev/null

ID1=`docker ps | grep $NAME | awk '{print $1}'`

sleep 2

# By now the log should be there
test_log_fc=`find /var/log/crawler_container_logs/watson_test.service_1.service_v003.$ID1/* | grep -c "test..log"`

if [ $test_log_fc == 0 ];
then
    echo 1;
else
    echo 0
fi

docker rm -f $NAME > /dev/null
