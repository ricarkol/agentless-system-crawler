FROM cloudsight/kelk-base

ENV ES_PKG_NAME elasticsearch-1.3.4
ENV KIBANA_PKG_NAME kibana-3.1.1

WORKDIR /opt

# Install Elasticsearch
RUN \
  wget -nv https://download.elasticsearch.org/elasticsearch/elasticsearch/$ES_PKG_NAME.tar.gz && \
  tar xzf $ES_PKG_NAME.tar.gz && \
  rm -f $ES_PKG_NAME.tar.gz && \
  mv $ES_PKG_NAME elasticsearch
COPY elasticsearch.yml /opt/elasticsearch/config/elasticsearch.yml

# Install Apache (to host Kibana)
RUN apt-get update && apt-get install -y apache2
RUN mkdir -p  /var/lock/apache2 /var/run/apache2

# Install Kibana
WORKDIR /var/www/html
RUN \
  wget -nv https://download.elasticsearch.org/kibana/kibana/$KIBANA_PKG_NAME.tar.gz && \
  tar xzf $KIBANA_PKG_NAME.tar.gz && \
  rm -f $KIBANA_PKG_NAME.tar.gz && \
  mv $KIBANA_PKG_NAME kibana

# Set CloudSight's Kibana dashboard as default
COPY cloudsight-dashboard.json /var/www/html/kibana/app/dashboards/default.json

# Configure supervisord
COPY start-elasticsearch.sh /opt/start-elasticsearch.sh
COPY startup-services.conf /etc/supervisor/conf.d/startup-services.conf

EXPOSE 9200 9300 80 
