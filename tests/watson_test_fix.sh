#!/bin/bash

for thefile in *; do
    sed -i.bak s/config_and_metrics_crawler/crawler/g thefile
done

