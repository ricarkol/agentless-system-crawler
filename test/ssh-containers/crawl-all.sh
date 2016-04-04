#!/bin/bash

CRAWLER_DIR=~/kollerr/cloudsight-container/collector/crawler
CRAWLER_FRAMES_DIR=/root/research/cloudsight-container/test/ssh-containers/frames
N=1 # number of crawls per image

. all_combinations

for i in "${arr[@]}"
do
	for n in `seq 1 $N`
	do
		IMAGE_ID=`uuid`
		docker tag $i $IMAGE_ID
		(cd ${CRAWLER_DIR}; bash crawl_docker_image_unsafe.sh $IMAGE_ID file://${CRAWLER_FRAMES_DIR}/$i null `uuid` `uuid` `uuid` `uuid` `uuid`)
	done
done
