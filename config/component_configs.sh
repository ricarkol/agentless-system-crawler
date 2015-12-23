#!/bin/bash

##################################
# Tunable variables
##################################

# Elasticsearch port used by the Search Service
ES_PORT=9200

# Host data directory to be used by Elasticsearch
ES_DATA_VOLUME=/mnt/data/elasticsearch/data

# Host log directory to be used by Elasticsearch
ES_LOGS_VOLUME=/mnt/data/elasticsearch/logs

# Elasticsearch heap size. This should not exceed half the 
# host's memory (leaving the other half to Lucene)
ES_HEAP_SIZE=16g

# Heap size to be used by Logstash
LS_HEAP_SIZE=5000m

# Kafka network config
KAFKA_PORT=9092

KAFKA_ZOO_KEEPER_PORT=2181

# Maximum message size Kafka will accept
KAFKA_MAX_MSG_SIZE=500000000 #(bytes)

# Host directory that will be used by Kafka to store the data ingested
KAFKA_DATA_VOLUME=/mnt/data/kafka/data

KAFKA_COMPLIANCE_TOPIC=compliance

KAFKA_VULNERABILITY_SCAN_TOPIC=vulnerabilityscan

USN_CRAWLER_DATA_DIR=/mnt/data/sec_data

# crawl repository every 24 hours
USN_CRAWLER_SLEEP_TIME=86400

#COMPLIANCE_UI_PORT=8181

#Regcrawler configuration
CONFIG_TOPIC=config
REGISTRY_TOPIC=registry-updates
NOTIFICATION_TOPIC=notification
INSECURE_REGISTRY=True
RUN_REGISTRY_UPDATE=True
REGISTRY_MONITOR_SINGLE_RUN=False
REGISTRY_UPDATE_PORT=8000
REGCRAWL_HOST_DATA_DIR="/mnt/data/regcrawler"
REGCRAWL_GUEST_DATA_DIR="/mnt/data/regcrawler"
REGISTRY_ICE_API=False

REGCRAWLER_DEB_FILE="regcrawler_0.4-alchemy_amd64.deb"

#config parser
CONFIG_PARSER_KNOWN_CONFIG_FILES='[\"/etc/passwd\",\"/etc/group\",\"/etc/shadow\",\"/etc/gshadow\",\"/etc/ssh/sshd_config\"]'

#log directories
HOST_CONTAINER_LOG_DIR=/var/log/cloudsight
CONTAINER_SUPERVISOR_LOG_DIR=/var/log/supervisor
CONTAINER_CLOUDSIGHT_LOG_DIR=/var/log/cloudsight
CONTAINER_KAFKA_LOG_DIR=/opt/kafka/logs
CLOUDSIGHT_DIR='cloudsight'
SUPERVISOR_DIR='supervisor'

#Logstash setup
LOGSTASH_DEB_FILE="mt-logstash-forwarder_0.3.2.20150617191910_all.deb"

#Timemachine Port
TIMEMACHINE_PORT=8600

#search service port
SEARCH_SERVICE=localhost:8885           # for now we assume that timemachine is deployed in the same cci as search service
SEARCH_SERVICE_PORT=8885
