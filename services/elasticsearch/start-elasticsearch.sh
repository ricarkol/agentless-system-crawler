#!/bin/bash

mkdir -p /var/log/elasticsearch
export ES_USE_GC_LOGGING=true

ES_HOSTS=`echo $ES_UNICAST_HOSTS | sed -e 's/,/","/' | sed -e 's/^/\["/' | sed -e 's/$/"\]/'`
sed -i s"/cluster.name:.*/cluster.name: $ES_CLUSTER_NAME/"  /opt/elasticsearch/config/elasticsearch.yml
sed -i s"/node.name:.*/node.name: $ES_NODE_NAME/" /opt/elasticsearch/config/elasticsearch.yml
sed -i s"/#network.publish_host:.*/network.publish_host: $ES_PUBLISH_HOST/" /opt/elasticsearch/config/elasticsearch.yml
sed -i s"/#discovery.zen.ping.multicast.enabled:.*/discovery.zen.ping.multicast.enabled: false/" /opt/elasticsearch/config/elasticsearch.yml
sed -i s"/#discovery.zen.ping.unicast.hosts:.*/discovery.zen.ping.unicast.hosts: $ES_HOSTS/" /opt/elasticsearch/config/elasticsearch.yml

/opt/elasticsearch/bin/elasticsearch
