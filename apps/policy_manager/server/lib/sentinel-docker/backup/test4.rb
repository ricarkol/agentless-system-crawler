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


rules = Rule.all

rule = rules.first
puts "org rule = #{JSON.pretty_generate(rule.as_json)}"
rule.description = "cc"
rule.save
puts "new rule = #{JSON.pretty_generate(rule.as_json)}"

