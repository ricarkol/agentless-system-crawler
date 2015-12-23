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
require 'sentinel-docker/scserver_control'

abort "Usage: #{$0} <clear|detail|history|sync|report> <options>" unless ARGV.length > 0

command = ARGV[0]

case ARGV[0]
when 'clear'
  SentinelDocker::DockerUtil.flash_data_cache
when 'detail'
  abort "Usage: #{$0} detail <namespace>" unless ARGV.length == 2
  SentinelDocker::DockerUtil.get_container_detail(ARGV[1])
when 'history'
  abort "Usage: #{$0} history <image_id>" unless ARGV.length == 2
  SentinelDocker::DockerUtil.get_image_history(ARGV[1])
when 'sync'  #trigger report gen
  abort "Usage: #{$0} sync <time * 10min>" unless ARGV.length == 2
  SentinelDocker::SCServerControl.request_server_sync 10*60*(ARGV[1].to_i)
when 'report'  #trigger report gen
  abort "Usage: #{$0} report" unless (ARGV.length == 1) 
  SentinelDocker::SCServerControl.request_page_update
when 'exec'  #trigger report gen
  abort "Usage: #{$0} exec <(containers)|any > <(rules)|any>" unless (ARGV.length == 3)
  containers = (ARGV[1]=='any' ? [] : ARGV[1].split(','))
  rules = (ARGV[2]=='any' ? [] : ARGV[2].split(','))
  SentinelDocker::DockerUtil.manual_run(containers, rules)
else
  abort "Usage: #{$0} <clear|detail|history|sync|report> <options>"
end
