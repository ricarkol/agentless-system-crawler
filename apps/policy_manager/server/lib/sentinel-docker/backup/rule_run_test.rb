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

include SentinelDocker::Models

begin
  SentinelDocker::Store.indices.create index: 'testing'
rescue
  puts 'Index not created. Already existed.'
end
SentinelDocker::Config.db.index_name = 'testing'

require 'sentinel-docker/models'

RULE_DIR = '/home/ruleadmin/newrules'

sleep(2)

# create user if it does not exist
user = Container.find(query: { 'identity' => 'ruleadmin' }).first
unless user
  user = User.new(identity: 'ruleadmin', fullname: 'rule administarator')
  puts "fail to save user" unless user.save
  puts "User created: #{JSON.pretty_generate(user.as_json)}"
end

Container.all.each do |container|

  container_rules = container.container_rules
  puts "----- rule execution -----"
  puts "container_id = #{container.container_id}"
  total = container_rules.size
  puts "trigger #{total} out of #{container.container_rules.size} rules"
  container_rules.each_with_index do |container_rule, i|
    puts "  container_rule = #{container_rule.id} #{i}/#{total}"
    puts "  script = #{container_rule.rule.script_path}"
    puts "  num of past runs : #{container_rule.container_rule_runs.size}"
    puts "  rule triggered"
    result = SentinelDocker::DockerUtil.run_rule(container_rule, user, true) # need async handling
    puts "    ==> result=#{JSON.pretty_generate(result)}"
  end

end
