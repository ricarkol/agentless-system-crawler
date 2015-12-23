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

user = SentinelDocker::Models::User.all.first
map = {}


(0...10).each do |i|
	SentinelDocker::Models::Container.all.each do |container|
		time1 = Time.now
		SentinelDocker::DockerUtil.get_crawl_times(container.namespace)
		puts "round #{i}: #{Time.now-time1}"
		break
	end
end
