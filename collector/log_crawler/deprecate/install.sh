#!/bin/bash
# Installs Logstash and the dependencies of config_shipper.py

pip install pyyaml

LOGSTASH_DIR=$1

BASE_DIR=/vagrant/collector/log_crawler

if [ ! -d $LOGSTASH_DIR ]; then
  echo "Installing Logstash"
  mkdir -p $LOGSTASH_DIR
  tar xzf $BASE_DIR/logstash-1.4.0.tar.gz -C $LOGSTASH_DIR --strip-components=1
fi

echo "Installing/configuring Tenjin"
pip install pyyaml
mkdir -p /tmp/tenjin
tar xzf $BASE_DIR/Tenjin-1.1.1.tar.gz -C /tmp/tenjin
cd /tmp/tenjin/Tenjin-1.1.1
python setup.py install
