#!/bin/bash


if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# tests the '.' in mount points are replaced with '#' to avoid
# unnecessary hierarchy in graphana
# Returns 1 if success, 0 otherwise

NAME=test_watson_namespace_mountpoint
HOST_NAMESPACE=dev/test
# Cleanup
rm -f /tmp/$NAME.*
rm -rf /var/log/crawler_container_logs/watson_test.service_1.service_v003.*/
docker rm -f $NAME 2> /dev/null > /dev/null

timeout 5 python2.7 ../config_and_metrics_crawler/crawler.py --crawlmode OUTCONTAINER \
	--features=disk \
    --environment watson \
	--linkContainerLogFiles --frequency 1 --numprocesses 1 \
	--url file:///tmp/$NAME --format graphite --namespace ${HOST_NAMESPACE} & #2>/dev/null &
PID=$!

echo 'uuid' >/tmp/set_component_env.sh
MSG=`uuid`
# /var/log/messages is linked by default. Here we test that adding it again won't do any harm.
docker run -d --name $NAME -v /tmp/set_component_env.sh:/etc/set_component_env.sh ubuntu  bash -c "\
    echo CLOUD_APP_GROUP=\'watson_test\' >>/etc/csf_env.properties; \
    echo CLOUD_APP=\'service_1\' >>/etc/csf_env.properties; \
    echo CLOUD_TENANT=\'public\' >>/etc/csf_env.properties; \
    echo CLOUD_AUTO_SCALE_GROUP=\'service_v003\' >>/etc/csf_env.properties; \
    echo CRAWLER_METRIC_PREFIX=watson_test.service_1.service_v003  >>/etc/csf_env.properties; \
    echo /var/log/test1.log >> /etc/logfiles;\
    echo /var/log/test2.log >> /etc/logfiles;\
    echo $MSG > /var/log/test1.log; \
    echo $MSG > /var/log/test2.log; \
    sleep 6000" 2> /dev/null > /dev/null

ID1=`docker ps | grep $NAME | awk '{print $1}'`

sleep 5

# By now the log should be there
count=`grep -c set-component-env#sh /tmp/$NAME.*.0`

# two values for each mounted point
if [ $count == 2 ];
then
    echo 1;
else
    echo 0
fi

docker rm -f $NAME > /dev/null
rm -rf /var/log/crawler_container_logs/dev.test.*
rm -f /tmp/$NAME.*
