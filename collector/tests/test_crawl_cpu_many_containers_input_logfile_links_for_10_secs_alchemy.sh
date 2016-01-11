#!/bin/bash

# Tests the OUTCONTAINER crawler mode for 32 containers
# Returns 1 if success, 0 otherwise

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

cat > /tmp/dummy-metadata-file << EOF
{"uuid": "<UUID>", "availability_zone": "nova", "hostname": "li-l6o5-3mvyy3m5ug3l-r2wazwiucexe-server-52l5wrw5277b.novalocal", "launch_index": 0, "meta": {"Cmd_0": "echo \"Hello world\"", "tagseparator": "_", "sgroup_name": "lindj_group1", "logging_password": "VSKHimqp69Nk", "Cmd_1": "/bin/bash", "tenant_id": "f75ec4e7-eb9d-463a-a90f-f8226572fbcc", "testvar1": "testvalue1", "sgroup_id": "dd28638d-7c10-4e26-9059-6e0baba7f64d", "test2": "supercoolvar2", "logstash_target": "logmet.stage1.opvis.bluemix.net:9091", "tagformat": "tenant_id group_id uuid", "metrics_target": "logmet.stage1.opvis.bluemix.net:9095", "group_id": "0000"}, "name": "li-l6o5-3mvyy3m5ug3l-r2wazwiucexe-server-52l5wrw5277b"}
EOF


COUNT=4

for i in `seq 1 $COUNT`
do
	CONTAINER_ID[$i]=`uuid`
	MSG=${CONTAINER_ID[$i]}

	rm -rf /var/log/crawler_container_logs/f75ec4e7-eb9d-463a-a90f-f8226572fbcc
	docker rm -f test_crawl_cpu_many_containers_$i 2> /dev/null > /dev/null
	docker run -d -e LOG_LOCATIONS=/var/log/input_file_name.log --name test_crawl_cpu_many_containers_$i \
		ubuntu bash -c "echo $MSG >> /var/log/input_file_name.log; sleep 5; echo $MSG >> /var/log/input_file_name.log; sleep 6000 " 2> /dev/null > /dev/null
	DOCKER_ID=`docker inspect -f '{{ .Id }}' test_crawl_cpu_many_containers_$i`

	# Create dummy metadata file
	mkdir -p /openstack/nova/metadata/
	sed s"/<UUID>/${CONTAINER_ID[$i]}/" /tmp/dummy-metadata-file > /openstack/nova/metadata/${DOCKER_ID}.json
done

IDS=`docker ps | grep test_crawl_cpu_many_containers | awk '{printf "%s,",  $1}' | sed s/,$//g`

timeout 10 python2.7 ../crawler/crawler.py --crawlmode OUTCONTAINER \
	--features=cpu --crawlContainers $IDS --numprocesses 2 \
	--frequency 1 --linkContainerLogFiles --environment alchemy 2> /dev/null > /dev/null

COUNT2=0
for i in `seq 1 $COUNT`
do
	MSG=${CONTAINER_ID[$i]}
	R=`grep -c $MSG /var/log/crawler_container_logs/f75ec4e7-eb9d-463a-a90f-f8226572fbcc/0000/${CONTAINER_ID[$i]}/var/log/input_file_name.log`
	COUNT2=$(($COUNT2 + $R))
done

for i in `seq 1 $COUNT`
do
	docker rm -f test_crawl_cpu_many_containers_$i > /dev/null
done

# In those 10 seconds, the containers had 2 logs
COUNT=$(($COUNT * 2))
if [ $COUNT == $COUNT2 ]
then
	echo 1
else
	echo 0
fi
