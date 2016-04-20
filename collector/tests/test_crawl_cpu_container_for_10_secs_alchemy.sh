#!/bin/bash

# Tests the OUTCONTAINER crawler mode and alchemy environment (using the
# --environment arg).  We pretend to run in the alchemy environment by creating
# a dummy metadata file artificially.
# Returns 1 if success, 0 otherwise

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

cat > /tmp/dummy-metadata-file << EOF
{"uuid": "<UUID>", "availability_zone": "nova", "hostname": "li-l6o5-3mvyy3m5ug3l-r2wazwiucexe-server-52l5wrw5277b.novalocal", "launch_index": 0, "meta": {"Cmd_0": "echo \"Hello world\"", "tagseparator": "_", "sgroup_name": "lindj_group1", "logging_password": "VSKHimqp69Nk", "Cmd_1": "/bin/bash", "tenant_id": "f75ec4e7-eb9d-463a-a90f-f8226572fbcc", "testvar1": "testvalue1", "sgroup_id": "dd28638d-7c10-4e26-9059-6e0baba7f64d", "test2": "supercoolvar2", "logstash_target": "logmet.stage1.opvis.bluemix.net:9091", "tagformat": "tenant_id group_id uuid", "metrics_target": "logmet.stage1.opvis.bluemix.net:9095", "group_id": "dd28638d-7c10-4e26-9059-6e0baba7f64d"}, "name": "li-l6o5-3mvyy3m5ug3l-r2wazwiucexe-server-52l5wrw5277b"}
EOF

COUNT=10
docker rm -f test_crawl_cpu_container_1 2> /dev/null > /dev/null
docker run -d --name test_crawl_cpu_container_1 ubuntu sleep 60 2> /dev/null > /dev/null
DOCKER_ID=`docker inspect -f '{{ .Id }}' test_crawl_cpu_container_1`

# Create dummy metadata file
CONTAINER_ID=`uuid`
sed -i s"/<UUID>/${CONTAINER_ID}/" /tmp/dummy-metadata-file
mkdir -p /openstack/nova/metadata/
mv /tmp/dummy-metadata-file /openstack/nova/metadata/${DOCKER_ID}.json

rm -f /tmp/test_crawl_cpu_container_for_10_secs_alchemy*

timeout $COUNT python2.7 ../config_and_metrics_crawler/crawler.py --crawlmode OUTCONTAINER \
	--features=cpu --crawlContainers ${DOCKER_ID} --frequency 1 \
	--environment alchemy \
	--url file:///tmp/test_crawl_cpu_container_for_10_secs_alchemy

cat /tmp/test_crawl_cpu_container_for_10_secs_alchemy* > /tmp/test_crawl_cpu_container_for_10_secs_alchemy

COUNT_CPU=`grep -c cpu-0 /tmp/test_crawl_cpu_container_for_10_secs_alchemy`
COUNT_METADATA=`grep -c f75ec4e7-eb9d-463a-a90f-f8226572fbcc.dd28638d-7c10-4e26-9059-6e0baba7f64d.${CONTAINER_ID} /tmp/test_crawl_cpu_container_for_10_secs_alchemy`

docker rm -f test_crawl_cpu_container_1 > /dev/null

if [ "7" -lt $COUNT_CPU ] && [ "7" -lt $COUNT_METADATA ]
then
	echo 1
else
	# XXX it's possible that once in a while some run might not get to
	# crawl 10 times
	echo 0
fi
