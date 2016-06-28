#!/bin/bash

# Tests the --linkContainerLogFiles option for the OUTCONTAINERcrawler mode .
# This option maintains symlinks for some logfiles inside the container. By
# default /var/log/messages and the docker (for all containers) are symlinked
# to a central location: /var/log/crawl_container_logs/...
# Returns 1 if success, 0 otherwise

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

cat > /tmp/dummy-metadata-file << EOF
{"uuid": "<UUID>", "availability_zone": "nova", "hostname": "li-l6o5-3mvyy3m5ug3l-r2wazwiucexe-server-52l5wrw5277b.novalocal", "launch_index": 0, "meta": {"Cmd_0": "echo \"Hello world\"", "tagseparator": "_", "sgroup_name": "lindj_group1", "logging_password": "VSKHimqp69Nk", "Cmd_1": "/bin/bash", "tenant_id": "f75ec4e7-eb9d-463a-a90f-f8226572fbcc", "testvar1": "testvalue1", "sgroup_id": "dd28638d-7c10-4e26-9059-6e0baba7f64d", "test2": "supercoolvar2", "logstash_target": "logmet.stage1.opvis.bluemix.net:9091", "tagformat": "tenant_id group_id uuid", "metrics_target": "logmet.stage1.opvis.bluemix.net:9095", "group_id": "0000"}, "name": "li-l6o5-3mvyy3m5ug3l-r2wazwiucexe-server-52l5wrw5277b"}
EOF

HOST_NAMESPACE=dev-test
MSG=`uuid`
NAME=test_crawl_cpu_container_log_links_1
rm -rf /var/log/crawler_container_logs/f75ec4e7-eb9d-463a-a90f-f8226572fbcc
docker rm -f $NAME 2> /dev/null > /dev/null
	docker run -d -e LOG_LOCATIONS=/var/log/input_file_name.log --name $NAME \
		ubuntu bash -c "echo $MSG >> /var/log/input_file_name.log; \
                                echo CLOUD_APP_GROUP=\'watson_test\' >>/etc/csf_env.properties; \
                                echo CLOUD_APP=\'service_1\' >>/etc/csf_env.properties; \
                                echo CLOUD_TENANT=\'public\' >>/etc/csf_env.properties; \
                                echo CLOUD_AUTO_SCALE_GROUP=\'service_v003\' >>/etc/csf_env.properties; \
                                echo CRAWLER_METRIC_PREFIX=watson_test.service_1.service_v003  >>/etc/csf_env.properties; \
                                sleep 6000" 2> /dev/null > /dev/null

timeout 5 python2.7 ../config_and_metrics_crawler/crawler.py --crawlmode OUTCONTAINER \
	--features=nofeatures --crawlContainers ${DOCKER_ID} \
	--linkContainerLogFiles --frequency 1 \
	--environment watson --namespace ${HOST_NAMESPACE} 2> /dev/null > /dev/null

ID1=`docker ps | grep $NAME | awk '{print $1}'`

sleep 5

# By now the log should be there                                                                                                            
test_log_fc=`find /var/log/crawler_container_logs/dev-test.watson_test.service_1.service_v003.$ID1/* | grep -c "input_file_name"`

if [ $test_log_fc == 0 ];
then
    echo 0;
else
    echo 1
fi

docker rm -f $NAME > /dev/null
