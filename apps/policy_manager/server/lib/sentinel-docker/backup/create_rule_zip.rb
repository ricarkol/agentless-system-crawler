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

include SentinelDocker::Models

RULE_DIR = '/home/ruleadmin/newrules'
RULE_ZIP_DIR = '/home/sentinel/rulezips'

Rule.all.each do |rule|
  temp_dir = Dir.mktmpdir
  begin
    rule_name = rule.name
    rule = Hashie::Mash.new(rule.as_json)
    attrs = rule.keys
    attrs.each do |k|
      rule.delete(k) unless rule[k]
    end
    rule.delete(:id)
    rule.delete(:rule_group_id)
    rule.delete(:rule_assign_group_id)
    File.write(File.join(temp_dir, 'metadata.json'), rule.to_json)
    pattern = File.join(RULE_DIR, "*#{rule_name}*")
    puts pattern
    Dir.glob(pattern).each do |f|
      puts "copied #{f}"
      FileUtils.cp(f, temp_dir)
    end
    zip_file_path = File.join(RULE_ZIP_DIR, "#{rule_name}.zip")
    `zip #{zip_file_path} -j #{temp_dir}/*`
  ensure
    FileUtils.remove_entry_secure temp_dir
  end
end

