#!/bin/bash

# Returns 1 if success, 0 otherwise

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

cat > /tmp/dummy-metadata-file << EOF
{"uuid": "<UUID>", "availability_zone": "nova", "hostname": "li-l6o5-3mvyy3m5ug3l-r2wazwiucexe-server-52l5wrw5277b.novalocal", "launch_index": 0, "meta": {"Cmd_0": "echo \"Hello world\"", "tagseparator": "_", "sgroup_name": "lindj_group1", "logging_password": "VSKHimqp69Nk", "Cmd_1": "/bin/bash", "tenant_id": "f75ec4e7-eb9d-463a-a90f-f8226572fbcc", "testvar1": "testvalue1", "sgroup_id": "dd28638d-7c10-4e26-9059-6e0baba7f64d", "test2": "supercoolvar2", "logstash_target": "logmet.stage1.opvis.bluemix.net:9091", "tagformat": "tenant_id group_id uuid", "metrics_target": "logmet.stage1.opvis.bluemix.net:9095", "group_id": "dd28638d-7c10-4e26-9059-6e0baba7f64d"}, "name": "li-l6o5-3mvyy3m5ug3l-r2wazwiucexe-server-52l5wrw5277b"}
EOF

HOST_IP=`python2.7 -c "$GET_HOST_IP_PY" 2> /dev/null`
NAME=test_create_destroy_containers_w_same_name_w_input_logfiles_alchemy
CONTAINER_ID=`uuid`
NAMESPACE=f75ec4e7-eb9d-463a-a90f-f8226572fbcc.dd28638d-7c10-4e26-9059-6e0baba7f64d.${CONTAINER_ID}
LOG_PATH="/var/log/crawler_container_logs/f75ec4e7-eb9d-463a-a90f-f8226572fbcc/dd28638d-7c10-4e26-9059-6e0baba7f64d/${CONTAINER_ID}"

# Cleanup
rm -f /tmp/$NAME*
rm -rf /var/log/crawler_container_logs/f75ec4e7-eb9d-463a-a90f-f8226572fbcc
docker rm -f $NAME 2> /dev/null > /dev/null

python2.7 ../config_and_metrics_crawler/crawler.py --crawlmode OUTCONTAINER \
	--features=cpu,interface --url file:///tmp/`uuid` \
	--linkContainerLogFiles --frequency 1 --numprocesses 4 \
	--url file:///tmp/$NAME --format graphite --environment alchemy 2>/dev/null &
PID=$!

MSG=`uuid`
docker run -d -e LOG_LOCATIONS=/var/log/input_file_name.log --name $NAME ubuntu bash -c "echo $MSG >> /var/log/input_file_name.log; sleep 5" 2> /dev/null > /dev/null
ID1=`docker ps | grep $NAME | awk '{print $1}'`

# Create dummy metadata file
DOCKER_ID=`docker inspect -f '{{ .Id }}' $NAME`
mkdir -p /openstack/nova/metadata/
sed s"/<UUID>/${CONTAINER_ID}/" /tmp/dummy-metadata-file > /openstack/nova/metadata/${DOCKER_ID}.json

sleep 3

# By now the log should be there
COUNT=`grep -c $MSG ${LOG_PATH}/var/log/input_file_name.log`

# Also, there should be cpu, and interface metrics for the container
COUNT_METRICS=`grep -l ${NAMESPACE}.interface-eth0 /tmp/${NAME}.${ID1}.* | wc -l`

# after this, the log will disappear
sleep 5

# By now the container should be dead, and the link should be deleted
if [ $COUNT == "1" ] && [ ! -f $LOG_PATH/var/log/input_file_name.log ] && [ ${COUNT_METRICS} -gt "0" ]
then
	:
	#echo 1
else
	echo 0
	exec 2> /dev/null
	kill $PID > /dev/null 2> /dev/null
	exit
fi

sleep 3

# Now start a container with the same name
MSG=`uuid`
# As the --ephemeral option to docker might not be available, lets make sure
# the container is removed (even if it already exited)
docker rm -f $NAME 2> /dev/null > /dev/null
docker run -d -e LOG_LOCATIONS=/var/log/input_file_name_2.log --name $NAME ubuntu bash -c "echo $MSG >> /var/log/input_file_name_2.log; sleep 5" 2> /dev/null > /dev/null
# Although this is a container with teh same name, the ID is not the same
ID2=`docker ps | grep $NAME | awk '{print $1}'`

# Create dummy metadata file
DOCKER_ID=`docker inspect -f '{{ .Id }}' $NAME`
mkdir -p /openstack/nova/metadata/
sed s"/<UUID>/${CONTAINER_ID}/" /tmp/dummy-metadata-file > /openstack/nova/metadata/${DOCKER_ID}.json

sleep 3

# By now the log should be there
COUNT=`grep -c $MSG ${LOG_PATH}/var/log/input_file_name_2.log`

# Also, there should be cpu, and interface metrics for the container
COUNT_METRICS=`grep -l ${NAMESPACE}.interface-eth0 /tmp/${NAME}.${ID2}.* | wc -l`

# after this, the log will disappear
sleep 5

# By now the container should be dead, and the link should be deleted
if [ $COUNT == "1" ] && [ ! -f $LOG_PATH/var/log/input_file_name_2.log  ] && [ ${COUNT_METRICS} -gt "0" ]
then
	echo 1
else
	echo 0
fi

# Just avoid having the "Terminated ..." error showing up
exec 2> /dev/null
kill $PID > /dev/null 2> /dev/null

docker rm -f $NAME > /dev/null
