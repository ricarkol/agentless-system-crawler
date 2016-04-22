FROM cloudsight/kelk-base

# These versions determine what kafka package will be installed
ENV KAFKA_VERSION 0.8.2.2
ENV SCALA_VERSION 2.11

WORKDIR /opt

# Install Kafka
RUN \
  wget -nv  http://apache.cs.utah.edu/kafka/$KAFKA_VERSION/kafka_$SCALA_VERSION-$KAFKA_VERSION.tgz && \
  tar xzf kafka_$SCALA_VERSION-$KAFKA_VERSION.tgz && \
  rm -f kafka_$SCALA_VERSION-$KAFKA_VERSION.tgz && \
  mv kafka_$SCALA_VERSION-$KAFKA_VERSION kafka

COPY start-kafka.sh /opt/start-kafka.sh
COPY vakcoc /opt/vakcoc
RUN chmod a+x /opt/start-kafka.sh
COPY vaKafkaServer.jks /opt/vaKafkaServer.jks

# Configure supervisord
COPY startup-services.conf /etc/supervisor/conf.d/startup-services.conf
