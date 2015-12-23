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

require 'hashie'
require 'logger'
require 'elasticsearch'
require 'net/https'
require 'uri'


CS_HOST = 'cloudsight.sl.cloud9.ibm.com'
CS_PORT = 8885
CS_ES_HOST = 'elastic2-cs.sl.cloud9.ibm.com'
CS_ES_PORT = 9200
CS_ES_MAX_RETURN = 1000
CloudSightStore = Elasticsearch::Client.new(hosts: [{ host: "#{CS_ES_HOST}", port: "#{CS_ES_PORT}" }], log: false)

def get_file_content(namespace, filepath)

  body = {
    query:{
      bool: {
        must: [
          { match: { 'namespace.raw' => namespace } },
          { match: { feature_type: 'config' } },
          { match: { 'feature_key.raw' => filepath } }
        ]
      }
    },
    sort:{ timestamp:{order:'desc'}},
    size:1
  }


  # index_date = Date.today
  # index = index_date.strftime("compliance-%Y.%m.%d")   # "compliance-2015.03.25"

  opts = {
    index: 'config-*',
    type: 'config_crawler',
    body: body,
    size: CS_ES_MAX_RETURN
  }

  response = Hashie::Mash.new(CloudSightStore.search(opts))
  results = response.hits.hits.map do |hit|
    hit._source
  end
  response.hits.hits.empty? ? nil : response.hits.hits.first._source

end

def get_history(namespace)

  body = {
    query: {
      bool: {
        must: [
          { term: { feature_type: 'dockerhistory' } },
          { term: { 'namespace.raw' => namespace } }
        ]
      }
    },
    sort: { "@timestamp" => { order: 'desc' } },
    size: 1
  }

  opts = {
    index: 'config-*',
    type: 'config_crawler',
    body: body,
    size: CS_ES_MAX_RETURN
  }

  response = Hashie::Mash.new(CloudSightStore.search(opts))

  results = response.hits.hits.map do |hit|
    hit._source
  end

  results.empty? ? nil : results.first

end

SUPPORTED_COMMANDS = ['content_match', 'base_image_check']

abort "Usage: #{$0} <#{SUPPORTED_COMMANDS.join('|')}> <namespace> <options>" if (ARGV.length < 2) || ! (SUPPORTED_COMMANDS.include? ARGV[0])

command = ARGV[0]
namespace = ARGV[1]
user_id = ENV['USER']


case command
when 'content_match'
  abort "Usage: #{$0} content_match <namespace> <file_path> <pattern>" unless ARGV.length == 4

  file_path = ARGV[2].split(',')
  pattern = ARGV[3]
  #get latest content
  content = {}

  matched = true
  result = nil
  file_path.each do |fp|
    content = get_file_content(namespace, fp)

    unless content
      result = {
        status: 'FAIL',
        output: "no content of #{fp} found in cloudsight",
        mode: 'check',
        crawl_time: 0,
        namespace: namespace,
        timestamp: Time.now.to_i,
        user: {identity: user_id}
      }
      break
    end

    unless content.config.content.match(/#{pattern}/)
      result = {
        status: 'FAIL',
        output: "The content of #{fp} does not match with pattern",
        mode: 'check',
        crawl_time: Time.parse(content.timestamp).to_i,
        namespace: namespace,
        timestamp: Time.now.to_i,
        user: {identity: user_id}
      }
      break
    end

  end

  unless result
    result = {
      status: 'PASS',
      output: "The files (#{file_path.join('|')}) matched with all patterns",
      mode: 'check',
      crawl_time: Time.parse(content.timestamp).to_i,
      namespace: namespace,
      timestamp: Time.now.to_i,
      user: {identity: user_id}
    }
  end

  puts result

when 'base_image_check'
  abort "Usage: #{$0} base_image_check <namespace> <image_id>" unless ARGV.length == 3
  image_id = ARGV[2]
  history = get_history(namespace)
  hit = history.dockerhistory.history.select do |h|
  	h.Id.start_with? image_id
  end
  if hit.empty?
    result = {
      status: 'FAIL',
      output: "The image is not built on the specified image <#{image_id}>",
      mode: 'check',
      crawl_time: Time.parse(history.timestamp).to_i,
      namespace: namespace,
      timestamp: Time.now.to_i,
      user: {identity: user_id}
    }
  else
    result = {
      status: 'PASS',
      output: "The image is built on the specified image <#{image_id}>",
      mode: 'check',
      crawl_time: Time.parse(history.timestamp).to_i,
      namespace: namespace,
      timestamp: Time.now.to_i,
      user: {identity: user_id}
    }
  end
  puts "#{JSON.pretty_generate(result)}"


else
  abort "Usage: #{$0} <#{SUPPORTED_COMMANDS.join('|')}> <options>"
end
