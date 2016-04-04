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
  module Util
    include SentinelDocker::Models

    Log = SentinelDocker::Log
    RULE_ZIP_DIR = '/home/sentinel/rulezips'


    def self.load_metadata(zipfile)
      rule = nil

      temp_dir = Dir.mktmpdir

      begin
        output = `unzip #{zipfile} -d #{temp_dir}`
        Log.debug "unzip output: #{output}"

        metadata = nil
        Dir::glob(File.join(temp_dir, "metadata.json")).each do |f|
          begin
            metadata = JSON.parse(File.read(f))
          rescue JSON::ParserError
            raise "fail to parse metadata.json"
          end
          break
        end

        metadata

      ensure
        FileUtils.rm_r(temp_dir)
      end

    end

    def self.set_rule(tenant, metadata, zipfile=nil, override=false)

      metadata = metadata.symbolize_keys
      metadata.slice(Rule.attributes)
      metadata.delete(:id)
      metadata.delete(:tenant_id)

      rule_name = metadata[:name]

      rule = Rule.find(query: { tenant_id: tenant.id, name: rule_name })
      if rule.empty?
        rule = Rule.new(metadata)
        rule.tenant_id = tenant.id
        fail rule.errors.full_messages.join(',') unless rule.save
      elsif override
        rule = rule.first
        rule.update!(metadata)
      else
        fail "Rule <#{rule_name}> already exists"
      end

      if zipfile
        rule_dir = File.join(RULE_ZIP_DIR, tenant.name)
        FileUtils.mkdir_p(rule_dir)
        FileUtils.cp(zipfile, File.join(rule_dir, rule_name))
        Log.debug "New rule: #{File.join(rule_dir, rule_name)}"
      end

      rule

    end

    def self.rule_zip_path(tenant, rule)
      return File.join(RULE_ZIP_DIR, tenant.name, rule.name)
    end

  end

end
