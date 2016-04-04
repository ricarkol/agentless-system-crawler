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
require 'rack/test'
require 'json'
require 'erb'

include Rack::Test::Methods
include SentinelDocker::Models

SentinelDocker::Config.db.index_name = 'testing'

CS_ES_HOST = 'elastic2-cs.sl.cloud9.ibm.com'
CS_ES_PORT = 9200
CS_INDEX = 'config-*'
CS_TYPE = 'config_crawler'
CS_ES_MAX_RETURN = 1000
CloudSightStore = Elasticsearch::Client.new(hosts: [{ host: "#{CS_ES_HOST}", port: "#{CS_ES_PORT}" }], log: false)


def app
  SentinelDocker::API::Root
end

def find_history(image_id)

  body = {
    query: {
      bool: {
        must: [
          {
            term: {
              feature_type: 'dockerhistory'
            }
          },
          {
            term: {
              namespace: image_id
            }
          }
        ]
      }
    },
    sort: {
      "@timestamp" => {
        order: 'desc'
      }
    },
    size: CS_ES_MAX_RETURN
  }

  opts = {
    index: CS_INDEX,
    type: CS_TYPE,
    body: body,
    size: CS_ES_MAX_RETURN
  }

  response = Hashie::Mash.new(CloudSightStore.search(opts))

  results = response.hits.hits.map do |hit|
    hit._source
  end
  results.size>0 ? results.first.dockerhistory.history : []

end


def getImageHistoryDot(vul_image_id = nil)

  get 'api/containers'
  containers = JSON.parse(last_response.body)
  rels={}
  vul_elms=[]
  containers.each do |container|
    
    get "api/images/#{container['image_id']}"
    image = JSON.parse(last_response.body)
    history = find_history(image['image_id'])

    child=nil
    history.each { |h|
      rels[child]=h.Id if child
      child=h.Id
    }

    isVul=false
    history.reverse_each { |h|
      if isVul
        vul_elms << h.Id
        next
      end
      if vul_image_id && h.Id==vul_image_id
        isVul=true
        vul_elms << h.Id
      end
    }

  end

  elms=rels.keys
  elms.concat(rels.values)
  elms.uniq!

  dot = "digraph evolve {"
  dot << "node [style=filled];"
  rev_map={}
  for i in 0..elms.size-1 do
    label = elms[i][0,12]
    #puts "#{label} in #{elms[i]}"
    # puts "n#{i} [label=\"#{label}\""
    dot << "n#{i} [label=\"#{label}\""
    if vul_elms.include?(elms[i])
      dot << " color=firebrick1"
    end
    dot << "];"
    rev_map[elms[i]]="n#{i}"
  end
  rels.each { |k,v|
    dot << "#{rev_map[v]} -> #{rev_map[k]};"
  }
  dot << "}"

  dot

end

def getImageHistoryGraph(image_id = nil)
  dot = getImageHistoryDot(image_id)
  file = Tempfile.new('tmp_dot')
  filepath = file.path
  file.close
  file.unlink
  File.write(filepath, dot)
  svg = ""
  begin
    svg = `dot -Tsvg #{filepath}`
  ensure
    File.delete(filepath)
  end
  return svg
end

  # get 'api/containers'
  # containers = JSON.parse(last_response.body)
  # rels={}
  # vul_elms=[]
  # containers.each do |container|
  #   puts "container_id=#{container['container_id']}"
  #   get "api/images/#{container['image_id']}"
  #   image = JSON.parse(last_response.body)
  #   puts "image_id=#{image['image_id']}"
  #   history = find_history(image['image_id'])
  #   puts "history=#{history}"
  # end
# dot = getImageHistoryDot
# puts dot

puts getImageHistoryGraph

