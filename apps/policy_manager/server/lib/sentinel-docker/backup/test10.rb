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


SentinelDocker::SCServerControl.request_server_sync

sleep 30

SentinelDocker::SCServerControl.request_page_update

sleep 30

user = SentinelDocker::Models::User.all.first
map = {}
SentinelDocker::Models::Container.all.each do |container|
container.container_rules.each do |cr|
  map[cr.id] = cr.container_rule_runs.size
  SentinelDocker::RuleRunner.request_new_run(cr, user)
end
break
end
