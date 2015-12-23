FROM cloudsight/kelk-base

ENV KAFKA_VERSION 0.8.2.0
ENV SCALA_VERSION 2.11
ENV LS_VERSION 1.4.2
ENV LS_KAFKA_VERSION 0.6.2

WORKDIR /opt

# Install Logstash
RUN wget -nv https://download.elasticsearch.org/logstash/logstash/logstash-$LS_VERSION.tar.gz && \
    tar xzf /opt/logstash-$LS_VERSION.tar.gz && \
    rm logstash-$LS_VERSION.tar.gz && \
    mv logstash-$LS_VERSION logstash

# Copy the CloudSight ConfigSplitter Logstash filter
COPY config_splitter.rb /opt/logstash/lib/logstash/filters/config_splitter.rb

# Install Kafka
RUN \
  wget -nv  http://apache.cs.utah.edu/kafka/$KAFKA_VERSION/kafka_$SCALA_VERSION-$KAFKA_VERSION.tgz && \
  tar xzf kafka_$SCALA_VERSION-$KAFKA_VERSION.tgz && \
  rm -f kafka_$SCALA_VERSION-$KAFKA_VERSION.tgz && \
  mv kafka_$SCALA_VERSION-$KAFKA_VERSION kafka

# Install Logstash-Kafka plugins
COPY logstash-kafka.tgz /opt/logstash-kafka.tgz
RUN \
#  wget -nv https://github.com/joekiller/logstash-kafka/archive/v$LS_KAFKA_VERSION.tar.gz && \
#  tar xzf v$LS_KAFKA_VERSION.tar.gz && \
#  rm v$LS_KAFKA_VERSION.tar.gz && \
#  mv logstash-kafka-$LS_KAFKA_VERSION logstash-kafka && \
  tar xzf logstash-kafka.tgz && \
  mkdir -p /opt/logstash/vendor/jar/kafka_$SCALA_VERSION-$KAFKA_VERSION/libs && \
  cp /opt/kafka/libs/* /opt/logstash/vendor/jar/kafka_$SCALA_VERSION-$KAFKA_VERSION/libs && \
  cp -r /opt/logstash-kafka/lib/logstash/* /opt/logstash/lib/logstash && \
  cd /opt/logstash && GEM_HOME=vendor/bundle/jruby/1.9 GEM_PATH= java -jar vendor/jar/jruby-complete-1.7.11.jar --1.9 ../logstash-kafka/gembag.rb ../logstash-kafka/logstash-kafka.gemspec
  
# Copy the Logstash indexer config file
COPY indexer.conf /etc/indexer.conf
COPY index-template.json /opt/index-template.json
COPY start-indexer.sh /opt/start-indexer.sh
RUN chmod a+x /opt/start-indexer.sh

# Configure supervisord
COPY startup-services.conf /etc/supervisor/conf.d/startup-services.conf
