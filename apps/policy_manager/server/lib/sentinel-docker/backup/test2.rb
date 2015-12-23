#!/bin/ruby
# coding: utf-8
# 
# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
require 'sentinel-docker'
require 'sentinel-docker/docker_util'

include SentinelDocker::Models

puts SentinelDocker::DockerUtil.put_data(:testindex, "key1", {aaa: "a1", bbb: "b1", timestamp:Time.now.to_i})
puts SentinelDocker::DockerUtil.get_data(:testindex, "key1")
puts SentinelDocker::DockerUtil.page_updated(:testindex, "key1").to_json
