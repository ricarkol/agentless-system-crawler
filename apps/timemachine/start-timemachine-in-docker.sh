#!/bin/bash
echo "elastic search host: $ELASTIC_SERVICE"
echo "search service host: $SEARCH_SERVICE"
/opt/timemachine/timemachine -v --search-service $SEARCH_SERVICE --elastic-search-cluster $ELASTIC_SERVICE --port $TIMEMACHINE_PORT
