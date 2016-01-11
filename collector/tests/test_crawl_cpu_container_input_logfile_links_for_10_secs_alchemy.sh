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

MSG=`uuid`
NAME=test_crawl_cpu_container_log_links_1
rm -rf /var/log/crawler_container_logs/f75ec4e7-eb9d-463a-a90f-f8226572fbcc
docker rm -f $NAME 2> /dev/null > /dev/null
docker run -d -e LOG_LOCATIONS=/var/log/messages,/var/log/input_file_name.log --name $NAME \
	ubuntu bash -c "echo $MSG >> /var/log/input_file_name.log; sleep 5; echo $MSG >> /var/log/input_file_name.log; sleep 6000 " 2> /dev/null > /dev/null
DOCKER_ID=`docker inspect -f '{{ .Id }}' $NAME`

# Create dummy metadata file
CONTAINER_ID=`uuid`
sed -i s"/<UUID>/${CONTAINER_ID}/" /tmp/dummy-metadata-file
mkdir -p /openstack/nova/metadata/
mv /tmp/dummy-metadata-file /openstack/nova/metadata/${DOCKER_ID}.json

timeout 10 python2.7 ../crawler/crawler.py --crawlmode OUTCONTAINER \
	--features=cpu --crawlContainers ${DOCKER_ID} \
	--linkContainerLogFiles --frequency 1 \
	--environment alchemy 2> /dev/null > /dev/null

COUNT=`grep -c $MSG /var/log/crawler_container_logs/f75ec4e7-eb9d-463a-a90f-f8226572fbcc/0000/${CONTAINER_ID}/var/log/input_file_name.log`

if [ $COUNT == "2" ]
then
	echo 1
else
	echo 0
fi

docker rm -f $NAME > /dev/null
