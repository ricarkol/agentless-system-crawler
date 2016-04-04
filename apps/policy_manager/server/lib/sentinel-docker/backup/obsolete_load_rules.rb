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
user = User.find(query: { 'identity' => 'ruleadmin' }).first
unless user
  user = User.new(identity: 'ruleadmin', fullname: 'rule administarator')
  puts "fail to save user" unless user.save
  puts "User created: #{JSON.pretty_generate(user.as_json)}"
end

# load_rule
Dir::glob(RULE_DIR+"/*.py").each do |fname|
  script_path = File.basename(fname)

#  next unless script_path == 'Comp-6-1-d.wtmp.py'
    
  next unless Rule.find(query: { 'script_path' => script_path }).empty?

  rule = Rule.new(name: script_path, script_path: script_path)
  if rule.save
    puts "Rule created: #{JSON.pretty_generate(rule.as_json)}"
  else
    puts "Fail to create rule : #{JSON.pretty_generate(rule.as_json)}"
  end
end

# load_crawled_data (periodically executed)
start_time = Time.now
max_days=45 #days
interval_before_start=15*24*60*60
interval_for_latest = 120
buffer_time = 10
begin_time = (start_time-max_days*24*60*60)
end_time = begin_time+interval_before_start

begin_time.utc
end_time.utc

docker_inspect_map = {}


loop do

  puts "searching namespaces from #{begin_time.iso8601} to #{end_time.iso8601}"
  namespaces = SentinelDocker::CloudsightUtil.get_namespaces(begin_time, end_time)
  new_containers = {}
  new_images = {}
  namespaces.each do |ns|
    

    if md = ns.match(/regcrawl-image-([0-9a-f]+)\/([0-9a-f]+)/)
      # crawl_times = SentinelDocker::CloudsightUtil.crawl_times(ns, begin_time, end_time)
      # new_containers[ns] = {
      #   image_id: md[1],
      #   container_id: md[2],
      #   crawl_times: crawl_times
      # }
      image_id = md[1]
      container_id = md[2]

#      next unless container_id == 'dcf1c6e1060d'

      next unless Container.find(query: { 'container_id' => container_id }).empty?

      detail = docker_inspect_map[image_id] || SentinelDocker::CloudsightUtil.get_container_detail(image_id)

      created = nil
      detail.each do |d|
        next unless d['dockerinspect.Id'][0...12] == container_id
        created = Time.iso8601(d['dockerinspect.Created']).to_i
      end
      created ||= 0  

      new_containers[ns] = {
        container_id: container_id, 
        container_name: container_id, #need to be retrieved from dockerinspect
        image_id: image_id, 
        created: created #need to be retrieved from dockerinspect
      }
    elsif md = ns.match(/regcrawl-image-([0-9a-f]+)/)
      # crawl_times = SentinelDocker::CloudsightUtil.crawl_times(ns, begin_time, end_time)
      # new_images[ns] = {
      #   image_id: md[1],
      #   crawl_times: crawl_times
      # }
      image_id = md[1]

      next unless Image.find(query: { 'image_id' => image_id }).empty?

      history = SentinelDocker::CloudsightUtil.get_image_history(image_id)

      created = nil
      image_tags = history['history'].first['Tags']
      image_tag = image_tags ? image_tags.first : nil
      #puts "image_tag=#{image_tag}, created=#{history['history'].first['Created']}"
      created = history['history'].first['Created'] ||= 0

      new_images[ns] = {
        image_id: image_id, 
        image_name: image_tag, #need to be retrieved from dockerinspect
        created: created #need to be retrieved from dockerinspect
      }
    else
      next
    end

  end
  puts "  ==> new containers: #{JSON.pretty_generate(new_containers)}" unless new_containers.empty?
  puts "  ==> new images: #{JSON.pretty_generate(new_images)}" unless new_images.empty?

  # create image
  new_images.each do |ns, conf|
    image = Image.new(conf)
    image.save
    new_images[ns] = image.id

    puts "Image created: #{JSON.pretty_generate(image.as_json)}"

  end

  # assign default rules
  rule_ids = Rule.all.map {|rule| rule.id}
  new_images.each do |ns, image_id|
    rule_ids.each do |rule_id|

      rule_assign_def = RuleAssignDef.new
      rule = Rule.get(rule_id)
      rule_assign_def.belongs_to(rule)
      rule_assign_def.save

      image_rule = ImageRule.new
      image = Image.get(image_id)
      image_rule.belongs_to(image)
      image_rule.belongs_to(rule_assign_def)
      image_rule.save

      puts "Rule <#{rule.script_path}> - Image <#{image.image_id}> linked"

    end
  end

  # create container
  new_containers.each do |ns, conf|
    image = Image.find(query: { 'image_id' => conf[:image_id] }).first
    unless image
      puts "no image #{conf[:image_id]} for container #{conf[:container_id]}"
      next
    end
    container = Container.new(conf)
    container.belongs_to(image)
    container.save
    puts "Container created: #{JSON.pretty_generate(container.as_json)}"
    new_containers[ns] = container
  end

  # trigger rule execution on containers

  Container.all.each do |container|

    container_rule_ids = container.container_rules.map {|cr| cr.id}

    triggered_container_rules = []

    container_rule_ids.each do |container_rule_id|
      container_rule = ContainerRule.get(container_rule_id)
      # next unless container_rule.rule.script_path.index('motd')
      past_run = container_rule.container_rule_runs.size
      next unless container_rule.container_rule_runs.size == 0
      triggered_container_rules << container_rule


    end

    unless triggered_container_rules.empty?
      puts "----- rule execution -----"
      puts "container_id = #{container.container_id}"
      total = triggered_container_rules.size
      puts "trigger #{total} out of #{container.container_rules.size} rules"
      triggered_container_rules.each_with_index do |container_rule, i|
        puts "  container_rule = #{container_rule.id} #{i}/#{total}"
        puts "  script = #{container_rule.rule.script_path}"
        puts "  num of past runs : #{container_rule.container_rule_runs.size}"
        puts "  rule triggered"
        rule_run = SentinelDocker::DockerUtil.run_rule(container_rule) # need async handling 
        puts "    ==> rule_run=#{JSON.pretty_generate(rule_run.as_json)}, total=#{container_rule.container_rule_runs.size}"
      end

    end

  end

  begin_time = end_time
  if end_time < start_time 
    end_time = [start_time, begin_time+interval_before_start].min
  else
    end_time = end_time+interval_for_latest
  end
  begin_time.utc
  end_time.utc

  puts "changed range from #{begin_time.iso8601} to #{end_time.iso8601}"

  secs = end_time - Time.now + buffer_time
  if secs > 0
    puts "waiting #{secs} seconds"
    sleep(secs)
  end

  begin_time -= buffer_time   

end

#show_report


# finalize
#SentinelDocker::Store.indices.delete index: 'testing'

# end of script


