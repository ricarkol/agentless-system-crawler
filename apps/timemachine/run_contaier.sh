#!/bin/bash

ELASTIC_SERVICE=deploy7.sl.cloud9.ibm.com:9200
SEARCH_SERVICE=deploy7.sl.cloud9.ibm.com:8885

container_id=`docker ps -a | grep "cloudsight_timemachine" |  cut -d' ' -f1`
if [[ "X$container_id" !=  "X" ]]; then
	echo "Removing previous timemachine_container $container_id"
	docker rm -f $container_id
fi
docker run -e ELASTIC_SERVICE=$ELASTIC_SERVICE -e SEARCH_SERVICE=$SEARCH_SERVICE -p 8600:8600 --name cloudsight_timemachine cloudsight/timemachine
