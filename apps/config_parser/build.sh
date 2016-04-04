#!/bin/bash


echo "###########################################"
echo "Building config parser docker images"
echo "###########################################"

set -ex

cs build -i cloudsight/config-parser --ignore-deps
