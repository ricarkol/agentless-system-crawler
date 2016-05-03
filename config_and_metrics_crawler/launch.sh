#!/bin/bash
# Start the crawler as a container.

# Arguments passed to this script will be passed to the crawler.
ENVIRONMENT=$1


echo $ENVIRONMENT
../../config/hosts.${ENVIRONMENT}
VA_CRAWLER_SPACE_ID="a63d60f6-d9ce-402a-9d06-b9263acc15d4"
VA_CRAWLER_EMIT_URL="mtgraphite://metrics.stage1.opvis.bluemix.net:9095/Crawler:5KilGEQ9qExi"
echo ${VA_CRAWLER_EMIT_URL}


CRAWLER_ARGS=`echo $@ | awk '{for (i = 2; i <= NF; i++) print $i}'`

case "$2" in
	help*)
		docker run -it crawler --help
	;;
	host*)
		docker run --privileged --net=host --pid=host \
			-v /cgroup:/cgroup \
			-v /sys/fs/cgroup:/sys/fs/cgroup \
			-v /var/run/docker.sock:/var/run/docker.sock \
			-it cloudsight/vacrawler --crawlmode INVM ${CRAWLER_ARGS}
	;;
	containers*)
	    CLOUDSIGHT_CRAWL_ENVIRONMENT="cloudsight"
	    CLOUDSIGHT_CRAWL_FEATURES="cpu,memory,interface,disk,os"
        CLOUDSIGHT_CRAWL_FORMAT="graphite"
        CLOUDSIGHT_CRAWL_FREQ="15"
        CLOUDSIGHT_CRAWL_MODE="OUTCONTAINER"
        NUM_CORES=8
        echo $$ > /var/run/va-crawler-containers.pid
        echo "[`date`] Creating /var/run/va-crawler-containers.pid" >> /var/log/va-crawler-containers_docker.log

        echo "[`date`] Starting crawler for environment: $CLOUDSIGHT_CRAWL_ENVIRONMENT" >> /var/log/va-crawler-containers_docker.log
        echo "[`date`] Sending frames to url: $VA_CRAWLER_EMIT_URL" >> /var/log/va-crawler-containers_docker.log
        echo "[`date`] Crawl features: $CLOUDSIGHT_CRAWL_FEATURES" >> /var/log/va-crawler-containers_docker.log
        echo "[`date`] Crawl format: $CLOUDSIGHT_CRAWL_FORMAT" >> /var/log/va-crawler-containers_docker.log
        echo "[`date`] Crawl frequency[s]: $CLOUDSIGHT_CRAWL_FREQ" >> /var/log/va-crawler-containers_docker.log
	    echo "STARTING"
	    echo $CLOUDSIGHT_CRAWL_EMIT_URL
		docker run --privileged --net=host --pid=host \
			-v /cgroup:/cgroup \
			-v /sys/fs/cgroup:/sys/fs/cgroup \
			-v /var/run/docker.sock:/var/run/docker.sock \
			-it cloudsight/vacrawler \
			--url "$VA_CRAWLER_EMIT_URL" \
			--since EPOCH \
			--frequency "$CLOUDSIGHT_CRAWL_FREQ" \
			--features "$CLOUDSIGHT_CRAWL_FEATURES" \
			--compress false \
			--logfile /var/log/va-crawler-containers_docker.log \
			--crawlContainers ALL \
			--format "$CLOUDSIGHT_CRAWL_FORMAT" \
			--crawlmode "$CLOUDSIGHT_CRAWL_MODE" \
			--environment "$CLOUDSIGHT_CRAWL_ENVIRONMENT" \
			--numprocesses "$NUM_CORES" \
			--namespace ${VA_CRAWLER_SPACE_ID}.va.`hostname` \
			2>> /var/log/va-crawler-containers_docker.log
	    echo "CONTAINER RUNNING"
	;;
	none*)
		docker run --privileged --net=host --pid=host \
			-v /cgroup:/cgroup \
			-v /sys/fs/cgroup:/sys/fs/cgroup \
			-v /var/run/docker.sock:/var/run/docker.sock \
			--entrypoint=/bin/bash \
			-it cloudsight/vacrawler
	;;
        *)
		echo $"Usage: $0 {host|containers|help|none}"
		exit 1
esac
