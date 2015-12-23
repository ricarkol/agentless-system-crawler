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
require 'sentinel-docker/models'

module SentinelDocker
  module AutoLoadUtil

    User = Models::User
    Container = Models::Container
    Image = Models::Image
    ImageRule = Models::ImageRule
    ContainerRule = Models::ContainerRule
    Rule = Models::Rule
    RuleAssignDef = Models::RuleAssignDef

    Config = Hashie::Mash.new(
      rule_dir: '/home/ruleadmin/newrules',
      local_es_host: 'elasticsearch',
      local_es_port: '9200',
      local_es_log_enabled: false,
      local_cache_index: 'local_cache',
      page_cache_enabled: true,
      data_cache_enabled: true
    )


    Local_Store = Elasticsearch::Client.new(hosts: [{ host: "#{Config.local_es_host}", port: "#{Config.local_es_port}" }], log: Config.local_es_log_enabled)

    begin
      SentinelDocker::Store.indices.create index: Config.local_cache_index
    rescue
    end

    def self.get_status_report(reload=false)
      data = Config.page_cache_enabled && !reload ? get_data(:pages, 'status_report') : nil
      if data && !reload
        data.page
      else 
        create_status_report
      end
    end

    def self.create_status_report
      page = `cd /opt/ibm/sentinel; bundle exec ruby lib/sentinel-docker/create_report.rb`
      put_data(:pages, 'status_report', {page: page})
      page
    end

    def self.config(conf)
      Config.rule_dir=conf[:rule_dir]
    end

    def self.init_user
      user = User.find(query: { 'identity' => 'ruleadmin' }).first
      # create user if it does not exist
      unless user
        user = User.new(identity: 'ruleadmin', fullname: 'rule administarator')
        puts "fail to save user" unless user.save
        puts "User created: #{JSON.pretty_generate(user.as_json)}"
      end
      user
    end

    def self.load_rules
      Dir::glob(Config.rule_dir+"/*.py").each do |fname|
        script_path = File.basename(fname)
        next unless /^Comp-.*/ =~ script_path
        next unless Rule.find(query: { 'script_path' => script_path }).empty?
        rule = Rule.new(name: script_path, script_path: script_path)
        if rule.save
          puts "Rule created: #{JSON.pretty_generate(rule.as_json)}"
        else
          puts "Fail to create rule : #{JSON.pretty_generate(rule.as_json)}"
        end
      end
    end

    def self.select_rules(container_rules)
      container_rule_ids = container_rules.map {|cr| cr.id}
      triggered_container_rules = []
      container_rule_ids.each do |container_rule_id|
        container_rule = ContainerRule.get(container_rule_id)
        # next unless container_rule.rule.script_path.index('motd')
        past_run = container_rule.container_rule_runs.size
        next unless container_rule.container_rule_runs.size == 0
        triggered_container_rules << container_rule
      end
      triggered_container_rules
    end

    def self.run_rules(container_rules)
      unless container_rules.empty?
        container_rules.each_with_index do |cr, i|
          puts "  script : #{cr.rule.script_path} (#{i}/#{container_rules.size})"
          puts "  num of past runs : #{cr.container_rule_runs.size}"
          puts "  rule triggered"
          rule_run = run_rule(cr)
          puts "    ==> rule_run=#{JSON.pretty_generate(rule_run.as_json)}, total=#{cr.container_rule_runs.size}"
        end
      end
    end

    def self.run_rule(container_rule)
      rule_run = SentinelDocker::DockerUtil.run_rule(container_rule) # need async handling
    end

    def self.assign_rule(image_id, rule_id)
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

    def self.create_image(conf)
      image = Image.find(query: { 'image_id' => conf[:image_id] }).first
      unless image
        puts "no image #{conf[:image_id]} for container #{conf[:container_id]}"
        return nil
      end
      container = Container.new(conf)
      container.belongs_to(image)
      container.save
      puts "Container created: #{JSON.pretty_generate(container.as_json)}"
      container
    end

    def self.put_data(type, key, data)

      result = Local_Store.update(
        index: Config.local_cache_index,
        type: type.to_s,
        id: key,
        refresh: true,
        body: { doc: {key: key, data: data}, doc_as_upsert: true }
      )
      result['_id']

    end

    def self.get_data(type, key)

      param = {
        index: "#{Config.local_cache_index}",
        type: type.to_s,
        body: {
          query: {
            ids: { values: [key] }
          }
        }
      }

      response = Hashie::Mash.new(Local_Store.search(param))
      results = response.hits.hits.map do |hit|
        hit._source.data
      end
      results.first
    end

    def self.flash_data_cache
      SentinelDocker::Store.indices.delete index: Config.local_cache_index
      SentinelDocker::Store.indices.create index: Config.local_cache_index
    end

    def self.get_container_detail(namespace, reload=false)

      detail = Config.data_cache_enabled && !reload ? get_data(:dockerinspect, namespace) : nil

      unless detail 
        return nil unless md = ns.match(/regcrawl-image-([0-9a-f]+)\/([0-9a-f]+)/)
        image_id = md[1]
        container_id = md[2]
        datails = SentinelDocker::CloudsightUtil.get_container_detail(image_id)
        details.each do |d|
          put_data(:dockerinspect, container_id, d)
          detail = d if d['dockerinspect.Id'][0...12] == container_id
        end
      end
      detail
    end

    def self.get_image_history(image_id, reload=false)
      data = Config.data_cache_enabled && !reload ? get_data(:dockerhistory, image_id) : nil
      unless data
        data = SentinelDocker::CloudsightUtil.get_image_history(image_id)
        put_data(:dockerhistory, image_id, data)
      end
      data
    end

    def self.parse_namespace(ns)

      conf = nil

      if md = ns.match(/regcrawl-image-([0-9a-f]+)\/([0-9a-f]+)/)
        image_id = md[1]
        container_id = md[2]
        if Container.find(query: { 'container_id' => container_id }).empty?
          detail = get_container_detail(container_id)
          created = Time.iso8601(detail['dockerinspect.Created']).to_i || 0
          conf = {
            container_id: container_id,
            container_name: container_id, #need to be retrieved from dockerinspect
            image_id: image_id,
            created: created #need to be retrieved from dockerinspect
          }
        end
      elsif md = ns.match(/regcrawl-image-([0-9a-f]+)/)
        image_id = md[1]
        if Image.find(query: { 'image_id' => image_id }).empty?

          history = get_image_history(image_id)
          created = nil
          image_tags = history['history'].first['Tags']
          image_tag = image_tags ? image_tags.first : nil
          #puts "image_tag=#{image_tag}, created=#{history['history'].first['Created']}"
          created = history['history'].first['Created'] ||= 0

          conf = {
            image_id: image_id,
            image_name: image_tag, #need to be retrieved from dockerinspect
            created: created #need to be retrieved from dockerinspect
          }
        end
      else
      end
      conf
    end

    def self.sync(begin_time, end_time)

      user=init_user
      load_rules


      updated = false
      puts "searching namespaces from #{begin_time.iso8601} to #{end_time.iso8601}"
      namespaces = SentinelDocker::CloudsightUtil.get_namespaces(begin_time, end_time)
      puts "namespaces = namespaces"
      new_containers = {}
      new_images = {}
      namespaces.each do |ns|
        puts "analize namespace <#{ns}>"
        conf = parse_namespace(ns)
        if conf
          if conf[:container_id]
            new_containers[ns] = conf
          else
            new_images[ns] = conf
          end
        end
      end

      updated = true unless new_images.empty? || new_containers.empty?

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
          assign_rule(image_id, rule_id)
        end
      end

      # create container
      new_containers.each do |ns, conf|
        new_containers[ns] = create_image(conf)
      end

      # trigger rule execution on containers

      Container.all.each do |container|
        container_rules = select_rules(container.container_rules)
        updated = true unless container_rules.empty?
        puts "container_id = #{container.container_id} trigger #{container_rules.size} out of #{container.container_rules.size} rules"
        run_rules(container_rules)
      end

      updated

    end
  end
end

