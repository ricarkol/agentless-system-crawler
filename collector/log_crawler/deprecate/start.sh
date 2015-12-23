#!/bin/bash
# Generates the Logstash configuration file and starts the log crawler

LOGSTASH_DIR=$1
BROKER_HOST=$2
LOG_TYPE=$3
BROKER_PORT=$4

BASE_DIR=/vagrant/collector/log_crawler
LOG_CRAWLER_CONFIG=$BASE_DIR/conf/log_crawler.yml
LS_CONFIG_TEMPLATE=$BASE_DIR/conf/shipper.conf.tenjin

TARGET_LOG_CRAWLER_CONFIG=$BASE_DIR/conf/log_crawler.$LOG_TYPE.yml
cp $LOG_CRAWLER_CONFIG.template $TARGET_LOG_CRAWLER_CONFIG
sed -i.bak "s/<<BROKER_HOST>>/${BROKER_HOST}/g" $TARGET_LOG_CRAWLER_CONFIG
sed -i.bak "s/<<TYPE>>/${LOG_TYPE}/g" $TARGET_LOG_CRAWLER_CONFIG
sed -i.bak "s/<<BROKER_PORT>>/${BROKER_PORT}/g" $TARGET_LOG_CRAWLER_CONFIG

rm $BASE_DIR/conf/*.bak

python $BASE_DIR/config_shipper.py $TARGET_LOG_CRAWLER_CONFIG $LS_CONFIG_TEMPLATE  >$LOGSTASH_DIR/shipper.conf

echo "Starting the log crawler"
pkill -f shipper.conf
nohup $LOGSTASH_DIR/bin/logstash -f $LOGSTASH_DIR/shipper.conf --pluginpath $BASE_DIR >/var/log/shipper.log 2>&1 &
