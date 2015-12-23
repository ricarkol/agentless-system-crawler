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
require 'zip'
require 'json'
require 'open3'

module SentinelDocker
  module SearchAPI

    Log = SentinelDocker::Log

    TIME_SYNC_GAP = 60*60
    SEARCH_TIME_RANGE = 60*60*3
    MAX_TRY = 2
    WAIT_SEC = 1

    RULE_SCRIPT_PATTERN = /^Comp.Linux.*/

    User = Models::User
    Container = Models::Container
    Image = Models::Image
    ImageRule = Models::ImageRule
    ContainerRule = Models::ContainerRule
    ContainerRuleRun = Models::ContainerRuleRun
    Rule = Models::Rule
    RuleAssignDef = Models::RuleAssignDef
    Tenant = Models::Tenant
    RuleAssignGroup = Models::RuleAssignGroup

    Config = Hashie::Mash.new(
      rule_dir: '/home/ruleadmin/newrules',
      local_es_host: 'elasticsearch',
      local_es_port: '9200',
      local_es_log_enabled: false,
      local_cache_index: 'local_cache',
      page_cache_enabled: true,
      data_cache_enabled: true,
      reports: {
        status_report: {
          cache_file:  '/opt/ibm/sentinel/tmp/status_report_cache',
          template_file: 'lib/sentinel-docker/status_report.erb'
        },
        vulnerability_report: {
          cache_file:  '/opt/ibm/sentinel/tmp/vulnerability_report_cache',
          template_file: 'lib/sentinel-docker/vulnerability_report.erb'
        }
      },
      use_stdout: true,
      check_interval: 12*60*60,  #12h
      backdate_period: 60*24*60*60     #60days
    )


    Local_Store = Elasticsearch::Client.new(hosts: [{ host: "#{Config.local_es_host}", port: "#{Config.local_es_port}" }], log: Config.local_es_log_enabled)

    begin
      SentinelDocker::Store.indices.create index: Config.local_cache_index
    rescue
    end

    # def self.get_data


    #   pedigree = {}
    #   images = Image.all
    #   images.each do |image|
    #     docker_image_id = image.image_id[0,12]
    #     history = SentinelDocker::DockerUtil.get_image_history(docker_image_id)
    #     next unless history
    #     child = nil
    #     history['history'].each do |h|
    #       parent = h['Id'][0,12]
    #       pedigree[child] = parent if child
    #       child = parent
    #     end
    #   end

    #   arr = []
    #   Container.all.each do |container|

    #     data = {}
    #     c = container.as_json
    #     c.delete_if { |k,v| k.to_s == 'image_id' }
    #     c.delete_if { |k,v| k.to_s == 'container_group_id' }
    #     c.delete_if { |k,v| k.to_s == 'host_id' }
    #     data.merge!(c)
    #     img = container.image.as_json
    #     img.delete_if { |k,v| k.to_s == 'id' }
    #     data.merge!(img)
    #     data.merge!({compliance: container.compliant? ? 'PASS' : 'FAIL'})
    #     container_rules = container.container_rules
    #     data.merge!({rules: container_rules.map {|cr| { status: cr.last_status, output: cr.last_output, timestamp: cr.last_timestamp } }})
    #     arr << data

    #   end

    #   arr
    # end

    def self.get_rules(namespace, owner_namespace)
      #resolve tenant and group from namespace
      #how to resolve ns
      tenant_id = nil
      t = Tenant.find(query: { 'tenant.owner_namespaces' => owner_namespace }).first
      fail 'no matechd tenant found' unless t

      image = Image.find(query: { 'namespace' => namespace }).first
      g = nil
      if image
        g = image.rule_assign_group
      else
        g = RuleAssignGroup.find(query: { 'tenant_id' => t.id, 'default' => true }).first
        
        image = Image.new(namespace: namespace, created: Time.now.to_i)
        image.belongs_to g
        image.save

        SentinelDocker::Log.debug("new image <#{image.id}> for #{namespace} has been created")

      end

      result = {}
      g.rules.each do |r|
        result[r.name] = {id: r.id, timestamp: r.timestamp}
      end
      result
    end

    def self.get_rules_per_tenant(tenant)
      t = Tenant.find(query: { 'tenant.name' => tenant }).first
      fail 'no tenant found' unless t
      arr = []
      t.rule_assign_groups.each do |g|
        arr << {group: g.name, value: g.rules.map{|r| r.name}}
      end
      arr
    end

    def self.get_image_status_per_tenant(tenant)

      t = Image.find(query: { 'tenant.name' => tenant }).first
      namespaces = SentinelDocker::CloudsightUtil.get_namespaces   
      arr = [] 
      namespaces.each do |namespace, res|
        image = Image.find(query: { 'namespace' => namespace }).first
        g = image.rule_assign_group if image

        latest_crawl_time = res[:crawl_times].first
        snapshot = SentinelDocker::CloudsightUtil.get_result(namespace, latest_crawl_time)

        arr << {
          namespace: namespace,
          group: g ? g.name : 'no_group',
          first_crawl: res[:crawl_times].last,
          latest_crawl: latest_crawl_time,
          latest_vul_result: snapshot[:vulnerability][:overall],
          latest_comp_result: snapshot[:compliance][:overall],
          auto_assigned: true,
          assigned_time: image ? image.assigned : nil
        }
      end
      arr
    end

    def self.get_rule_assign_groups(tenant)
      t = Tenant.find(query: { 'tenant.name' => tenant }).first
      fail 'no tenant found' unless t
      arr = []
      t.rule_assign_groups.each do |g|
        arr << {name: g.name}
      end
      arr
    end


    def self.get_tenant_rules(tenant, group)
      t = Tenant.find(query: { 'tenant.name' => tenant }).first
      fail 'no tenant found' unless t
      rule_assign_group = nil
      if group
        rule_assign_group = t.rule_assign_groups.select { |gr| gr.name == group }
      else
        rule_assign_group = t.rule_assign_groups.select { |gr| gr.default == true }
      end
      fail 'no group found' if rule_assign_group.empty?
      arr = []
      rule_assign_group[0].rules.each do |r|
        r = r.as_json
        r.delete(:rule_group_id)
        r.delete(:rule_assign_group_id)
        r.delete('rule_group_id')
        r.delete('rule_assign_group_id')
        r.delete('version')
        r.delete('attrs')
        r.delete('parameters')
        r.delete('grace_period')
        arr << r
      end
      arr
    end

    def self.set_namespaces_to_group(tenant, group, conf) 

      t = Tenant.find(query: { 'tenant.name' => tenant }).first
      fail "tenant <#{tenant}> cannot be found" unless t
      rule_assign_group = t.rule_assign_groups.select { |gr| gr.name == group }
      fail "rule assign group <#{group}> cannot be found" unless rule_assign_group

      images = []
      begin
        arr = JSON.parse(conf)
        arr.each do |namespace|
          image = Image.find(query: { 'image.namespace' => namespace }).first
          fail "invalid namespace : #{namespace}" unless image
          images << image
        end
      rescue JSON::ParserError
        fail "array of namespaces must be in body"
      end

      images.each do |image|
        image.belongs_to(rule_assign_group)
        image.save
      end

    end

    def self.set_tenant_rules(tenant, group, conf, default=false) 

      t = Tenant.find(query: { 'tenant.name' => tenant }).first

      fail "tenant <#{tenant}> cannot be found" unless t

      rule_assign_group = t.rule_assign_groups.select { |gr| gr.name == group }

      if rule_assign_group.empty?
        SentinelDocker::Log.debug("new group <#{group}> is created")
        #create new group
        rule_assign_group = RuleAssignGroup.new(name: group)
        rule_assign_group.tenant_id = t.id
      else
        SentinelDocker::Log.debug("group <#{group}> is updated")
        rule_assign_group = rule_assign_group.first
      end

      rule_ids = []
      begin
        arr = JSON.parse(conf)
        arr.each do |rule_id|
          r = Rule.get(rule_id)
          fail "invalid rule : #{rule_id}" unless r
          rule_ids << rule_id
        end
      rescue JSON::ParserError
        fail "array of rule ids must be in body"
      end

      rule_assign_group.rule_id = rule_ids

      if default && !rule_assign_group.default
        default_rule_assign_group = t.rule_assign_groups.select { |gr| gr.default == true }.first
        default_rule_assign_group.default = false
        default_rule_assign_group.save
        rule_assign_group.default = true
        SentinelDocker::Log.debug("default group is changed from #{default_rule_assign_group.name} to #{rule_assign_group.name}")
      end

      fail rule_assign_group.errors.full_messages.join(',') unless rule_assign_group.save

      ''
    end

  end

end
