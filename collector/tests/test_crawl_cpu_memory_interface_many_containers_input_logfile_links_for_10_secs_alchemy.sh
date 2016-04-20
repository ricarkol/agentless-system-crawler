#!/bin/bash

# Tests the OUTCONTAINER crawler mode for 32 containers
# Returns 1 if success, 0 otherwise

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

CRAWLER_CODE=../config_and_metrics_crawler/crawler.py

cat > /tmp/dummy-metadata-file << EOF
{"uuid": "<UUID>", "availability_zone": "nova", "hostname": "li-l6o5-3mvyy3m5ug3l-r2wazwiucexe-server-52l5wrw5277b.novalocal", "launch_index": 0, "meta": {"Cmd_0": "echo \"Hello world\"", "tagseparator": "_", "sgroup_name": "lindj_group1", "logging_password": "VSKHimqp69Nk", "Cmd_1": "/bin/bash", "tenant_id": "<SPACE_ID>", "testvar1": "testvalue1", "sgroup_id": "dd28638d-7c10-4e26-9059-6e0baba7f64d", "test2": "supercoolvar2", "logstash_target": "logmet.stage1.opvis.bluemix.net:9091", "tagformat": "tenant_id group_id uuid", "metrics_target": "logmet.stage1.opvis.bluemix.net:9095", "group_id": "0000"}, "name": "li-l6o5-3mvyy3m5ug3l-r2wazwiucexe-server-52l5wrw5277b"}
EOF


COUNT=4

for i in `seq 1 $COUNT`
do
	SPACE_ID[$i]=`uuid`
	CONTAINER_ID[$i]=`uuid`
	MSG=${CONTAINER_ID[$i]}

	docker rm -f test_crawl_cpu_many_containers_$i 2> /dev/null > /dev/null
	docker run -d -e LOG_LOCATIONS=/var/log/input_file_name.log --name test_crawl_cpu_many_containers_$i \
		ubuntu bash -c "echo $MSG >> /var/log/input_file_name.log; echo $MSG; sleep 5; echo $MSG >> /var/log/input_file_name.log; echo $MSG; sleep 6000 " 2> /dev/null > /dev/null
	DOCKER_ID=`docker inspect -f '{{ .Id }}' test_crawl_cpu_many_containers_$i`

	# Create dummy metadata file
	mkdir -p /openstack/nova/metadata/
	cp /tmp/dummy-metadata-file /openstack/nova/metadata/${DOCKER_ID}.json
	sed -i s"/<UUID>/${CONTAINER_ID[$i]}/" /openstack/nova/metadata/${DOCKER_ID}.json
	sed -i s"/<SPACE_ID>/${SPACE_ID[$i]}/" /openstack/nova/metadata/${DOCKER_ID}.json
done

IDS=`docker ps | grep test_crawl_cpu_many_containers | awk '{printf "%s,",  $1}' | sed s/,$//g`

rm -rf /tmp/alchemy_all_test*

timeout 10 python2.7 ${CRAWLER_CODE} --crawlmode OUTCONTAINER \
	--features=cpu,memory,interface --crawlContainers $IDS --numprocesses 2 \
	--frequency 1 --linkContainerLogFiles --environment alchemy --format graphite \
	--url file:///tmp/alchemy_all_test 2> /dev/null > /dev/null

cat /tmp/alchemy_all_test* > /tmp/alchemy_all_test

# Example data in graphite format:
#f75ec4e7-eb9d-463a-a90f-f8226572fbcc.0000.4f768e88-a05a-11e5-9ac0-06427acb060b.cpu-0.cpu-idle 100.000000 1449874547
#f75ec4e7-eb9d-463a-a90f-f8226572fbcc.0000.4f768e88-a05a-11e5-9ac0-06427acb060b.memory.memory-free 308715520.000000 1449874547
#f75ec4e7-eb9d-463a-a90f-f8226572fbcc.0000.4f768e88-a05a-11e5-9ac0-06427acb060b.interface-lo.if_octets.tx 0.000000 1449874547

COUNT_CPU=0
COUNT_MEM=0
COUNT_INTERFACE=0
for i in `seq 1 $COUNT`
do
	NAMESPACE=${SPACE_ID[$i]}.0000.${CONTAINER_ID[$i]}
	TMP_COUNT_CPU=`grep -c ${NAMESPACE}.cpu-0.cpu-idle /tmp/alchemy_all_test`
	TMP_COUNT_MEM=`grep -c ${NAMESPACE}.memory.memory-free /tmp/alchemy_all_test`
	TMP_COUNT_INTERFACE=`grep -c ${NAMESPACE}.interface-eth0.if_octets.tx /tmp/alchemy_all_test`
	COUNT_CPU=$(($COUNT_CPU + $TMP_COUNT_CPU))
	COUNT_MEM=$(($COUNT_MEM + $TMP_COUNT_MEM))
	COUNT_INTERFACE=$(($COUNT_INTERFACE + $TMP_COUNT_INTERFACE))
done

COUNT_INPUT_LOG_FILE=0
COUNT_DOCKER_LOG=0
for i in `seq 1 $COUNT`
do
	MSG=${CONTAINER_ID[$i]}
	R=`grep -c $MSG /var/log/crawler_container_logs/${SPACE_ID[$i]}/0000/${CONTAINER_ID[$i]}/var/log/input_file_name.log`
	COUNT_INPUT_LOG_FILE=$(($COUNT_INPUT_LOG_FILE + $R))
	R=`grep -c $MSG /var/log/crawler_container_logs/${SPACE_ID[$i]}/0000/${CONTAINER_ID[$i]}/docker.log`
	COUNT_DOCKER_LOG=$(($COUNT_DOCKER_LOG + $R))
done

for i in `seq 1 $COUNT`
do
	docker rm -f test_crawl_cpu_many_containers_$i > /dev/null
done

# In those 10 seconds, the containers had 2 logs
COUNT=$(($COUNT * 2))
if [ $COUNT == $COUNT_INPUT_LOG_FILE ] && [ $COUNT == $COUNT_DOCKER_LOG ] && [ "10" -lt $COUNT_CPU ] && [ "10" -lt $COUNT_MEM ] && [ "10" -lt $COUNT_INTERFACE ] 
then
	echo 1
else
	echo 0
fi
