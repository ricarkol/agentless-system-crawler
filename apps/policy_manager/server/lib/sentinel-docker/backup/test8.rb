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


module Test8


  def self.get_latest_crawl_time(namespace)

    if namespace = ns.match(/regcrawl-image-([0-9a-f]+)\/([0-9a-f]+)/)
        image_id = md[1]
        container_id = md[2]
        image_namespace = "regcrawl-image-#{image_id}"
    else
      return nil
    end

    body = {
      query:{
        bool: {
          must: [
            {
              term: {
                feature_type: 'dockerinspect'
              }
            },
            {
              term: {
                "namespace.raw" => image_namespace
              }
            },
            {
              wildcard: {
                "dockerinspect.Id" => {
                  "value" => "#{container_id}*"
                }
              }
            }
          ]
        }
      },
      sort: {
        timestamp: {
          order: 'desc'
        }
      },
      fields: [
        'namespace',
        'dockerinspect.Name',
        'dockerinspect.Image',
        'dockerinspect.Id',
        'dockerinspect.Created',
        'timestamp',
        '@timestamp'
      ],
      size: 1
    }

    opts = {
      index: 'config-*',
      type: 'config_crawler',
      body: body,
      size: CS_ES_MAX_RETURN
    }

    response = Hashie::Mash.new(CloudSightStore.search(opts))
    result = response.hits.hits.first
    result.empty? ?  nil : result.fields.timestamp.first

  end

end




user = SentinelDocker::Models::User.all.first
map = {}
SentinelDocker::Models::Container.all.each do |container|
  container.container_rules.each do |cr|
    map[cr.id] = cr.container_rule_runs.size
    SentinelDocker::RuleRunner.request_new_run(cr, user)
  end
  break
end
