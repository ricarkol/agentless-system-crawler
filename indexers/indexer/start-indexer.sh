#!/bin/bash

# Point Logstash's Kafka input plugin to Kafka's zookeeper.
if [ "$ZK_IP" == "" ]; then
  # The IP of kafka's Zookeeper has not been set. Assume 'localhost'
  ZK_IP="localhost"
fi

sed -i s"/<ZK_HOST>/$ZK_IP/" /etc/indexer.conf
sed -i s"/<MAX_MSG_SIZE>/$KAFKA_MAX_MSG_SIZE/" /etc/indexer.conf
sed -i s"/<HOST_IP>/$HOST_IP/" /etc/indexer.conf
sed -i s"/<PROCESSOR_ID>/$PROCESSOR_ID/" /etc/indexer.conf
sed -i s"/<CONTAINER_NAME>/$CONTAINER_NAME/" /etc/indexer.conf

/opt/logstash/bin/logstash agent -f /etc/indexer.conf 
