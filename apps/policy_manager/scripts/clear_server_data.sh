#!/bin/bash
curl -XDELETE http://elasticsearch:9200/testing;cdir=`pwd`;cd /opt/ibm/sentinel;kill `ps -ef | grep -e "puma 2.8.2" | awk '{print $2 "\t" $8}' | grep puma | cut -f 1`;./scripts/server -d;sudo -u sentinel /opt/rbenv/shims/bundle exec ruby lib/sentinel-docker/populate_rule_data.rb;cd $cdir
