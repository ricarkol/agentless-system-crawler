SEARCH_IP=`curl -s http://localhost:8080/csf-sidecar-netflixoss/eureka/apps/CLOUDSIGHT_SEARCH_SERVICE/ | jq ".instances[0].hostName" | sed 's/"//g'`
SEARCH_PORT=`curl -s http://localhost:8080/csf-sidecar-netflixoss/eureka/apps/CLOUDSIGHT_SEARCH_SERVICE/ | jq ".instances[0].port" `
SEARCH_URL=http://$SEARCH_IP:$SEARCH_PORT
echo  "Search Service @ $SEARCH_URL"

KAFKA_HOSTS=`curl -s http://localhost:8080/csf-sidecar-netflixoss/eureka/apps/CSF_ELK_KAFKA/`
KAFKA_IP=`echo $KAFKA_HOSTS | jq ".instances[0].hostName" | sed 's/"//g'`
KAFKA_PORT=`echo $KAFKA_HOSTS | jq ".instances[0].port" `
KAFKA_PORT=9092
KAFKA_URL=$KAFKA_IP:$KAFKA_PORT
echo "Kafka Service @ $KAFKA_URL"

/usr/bin/python  /home/cloudadmin/scanner-commandline-tool/scanner-reading-from-elasticsearch.py --elasticsearch-wrapper-server-url $SEARCH_URL --kafka_url $KAFKA_URL  --begin_time `date --date "2015-02-10" "+%s"`  --end_time  `date --date "2015-04-15" "+%s"`

