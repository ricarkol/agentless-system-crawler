#!/bin/bash

# Make sure Kafka's advertised hostname can be resolved by producers/consumers
if [ "$HOST_IP" == "" ]; then
  # The HOST_IP variable was not set by the user. Assume 'localhost'.
  HOST_IP="localhost"
fi
sed -i s"/#advertised\.host\.name=.*/advertised\.host\.name=$HOST_IP/" /opt/kafka/config/server.properties
sed -i s"/socket.request.max.bytes=.*/socket.request.max.bytes=$KAFKA_MAX_MSG_SIZE/" /opt/kafka/config/server.properties
sed -i s"/num.partitions=.*/num.partitions=10/" /opt/kafka/config/server.properties
sed -i s"/num.network.threads=.*/num.network.threads=10/" /opt/kafka/config/server.properties
sed -i s"/broker.id=*/broker.id=$PROC_ID/" /opt/kafka/config/server.properties
sed -i s"/zookeeper.connect=*/zookeeper.connect=$ZOOKEEPER_CLUSTER/" /opt/kafka/config/server.properties
sed -i s"/clientPort=*/clientPort=$KAFKA_ZOOKEEPER_PORT/" /opt/kafka/config/server.properties

# Increase the java heap size to 4GBs Don't want to exagerate with this,
# because kafka is supposed to use memory mapped pages from the page cache and
# not from it's own java heap (anon pages).  Also, based on what the linkedin
# people are doing in production: 3GBs for a 32GB host
# (https://kafka.apache.org/08/ops.html).

sed -i s"/-Xmx1G -Xms1G/-Xmx4G -Xms4G/" /opt/kafka/bin/kafka-server-start.sh

if [ "$KAFKA_MAX_MSG_SIZE" != "" ]; then
  # User wants to explicitly set Kafka's maximum message size.
  echo "
#################
#################
message.max.bytes=$KAFKA_MAX_MSG_SIZE
replica.fetch.max.bytes=$KAFKA_MAX_MSG_SIZE
#################
#################

# Log retention of 2 days
log.retention.hours=48
# The total log directory can not be larger than 1TB
log.retention.size=1073741824000
# Each log file can not be larger than 1GB
log.file.size=1073741824
" >> /opt/kafka/config/server.properties
fi

jmx_parms=" \
-Dcom.sun.management.jmxremote \
-Dcom.sun.management.jmxremote.authenticate=false \
-Dcom.sun.management.jmxremote.local.only=false \
-Dcom.sun.management.jmxremote.ssl=true \
-Dcom.sun.management.jmxremote.registry.ssl=true \
-Djavax.net.ssl.keyStore=/opt/vaKafkaServer.jks \
-Djavax.net.ssl.keyStoreType=jks \
-Djavax.net.ssl.keyStorePassword=vaServerPass \
"

echo "#!/bin/bash" > /opt/boot_kafka.sh
echo export JMX_PORT=$KAFKA_JMX_PORT >> /opt/boot_kafka.sh
echo 'export KAFKA_JMX_OPTS="'${jmx_parms}' -Dcom.sun.management.jmxremote.rmi.port=$KAFKA_JMX_PORT -Djava.rmi.server.hostname=$HOST_IP"' >> boot_kafka.sh
echo '/opt/kafka/bin/kafka-server-start.sh $*' >> /opt/boot_kafka.sh
chmod +x /opt/boot_kafka.sh

echo "#!/bin/bash" > /opt/boot_zookeeper.sh
echo export JMX_PORT=$KAFKA_ZOOKEEPER_JMX_PORT >> /opt/boot_zookeeper.sh
echo 'export KAFKA_JMX_OPTS="'${jmx_parms}' -Dcom.sun.management.jmxremote.rmi.port=$KAFKA_ZOOKEEPER_JMX_PORT -Djava.rmi.server.hostname=$HOST_IP"' >> boot_zookeeper.sh
echo '/opt/kafka/bin/zookeeper-server-start.sh $*' >> /opt/boot_zookeeper.sh
chmod +x /opt/boot_zookeeper.sh

# Tell supervisord that it now can start kafka
/usr/bin/supervisorctl restart zookeeper
/usr/bin/supervisorctl restart kafka
