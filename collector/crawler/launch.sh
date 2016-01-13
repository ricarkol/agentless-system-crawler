#!/bin/bash

case "$1" in
	host*)
		docker run --privileged --net=host --pid=host \
			-v /cgroup:/cgroup \
			-v /sys/fs/cgroup:/sys/fs/cgroup \
			-v /var/run/docker.sock:/var/run/docker.sock \
			-it crawler --crawlmode INVM
	;;
	containers*)
		docker run --privileged --net=host --pid=host \
			-v /cgroup:/cgroup \
			-v /sys/fs/cgroup:/sys/fs/cgroup \
			-v /var/run/docker.sock:/var/run/docker.sock \
			-it crawler --crawlmode OUTCONTAINER
	;;
esac
