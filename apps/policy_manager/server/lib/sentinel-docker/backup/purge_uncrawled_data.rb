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
require 'sentinel-docker/rule_runner'
require 'sentinel-docker/scserver_control'

containers = SentinelDocker::Models::Container.all
containers.each_with_index do |container, i|
  namespace = container.namespace 
  puts "namespace=#{namespace} (#{i}/#{containers.size})"
  times = SentinelDocker::DockerUtil.get_crawl_times(namespace)
  timestamp = times.empty? ? nil : times.first
  puts "timestamp=#{timestamp}"
  cmd = "sudo -u ruleadmin bash -c 'cd /home/ruleadmin/newrules; /usr/bin/python PurgeUncrawledData.py #{namespace} #{timestamp}'"
  puts "cmd=#{cmd}"
  output = `#{cmd}`
  puts "output=#{output}"
end
