#!/bin/bash

# Point the Search Service to the target Elasticsearch
if [ "$ES_IP" == "" ]; then
  # The IP of Elasticsearch has not been set. Assume 'localhost'
  ES_IP="localhost"
fi

search --es $ES_IP:$ES_PORT --port $SEARCH_SERVICE_PORT
