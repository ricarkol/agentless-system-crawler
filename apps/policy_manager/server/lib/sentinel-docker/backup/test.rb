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

#page_key = 'status_report'
page_key = 'vulnerability_report'
exists = SentinelDocker::DockerUtil.flash_data_cache
puts "flash cache : #{exists ? 'success' : 'false'}"
start_time = Time.now
SentinelDocker::DockerUtil.get_report(page_key, false)
puts "1 : #{Time.now - start_time}"
SentinelDocker::DockerUtil.get_report(page_key, false)
puts "2 : #{Time.now - start_time}"
SentinelDocker::DockerUtil.get_report(page_key, true)
puts "3 : #{Time.now - start_time}"
SentinelDocker::DockerUtil.get_report(page_key, false)
puts "4 : #{Time.now - start_time}"
exists = SentinelDocker::DockerUtil.flash_data_cache
puts "flash cache : #{exists ? 'success' : 'false'}"
SentinelDocker::DockerUtil.get_report(page_key, true)
puts "5 : #{Time.now - start_time}"
SentinelDocker::DockerUtil.get_report(page_key, false)
puts "6 : #{Time.now - start_time}"
