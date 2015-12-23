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

module SentinelDocker
  module CloudsightUtil

    # CS_HOST = 'demo3.sl.cloud9.ibm.com'
    # CS_PORT = '9200'
    # CS_INDEX = 'config-2015.02.13'
    # CS_TYPE = 'config_crawler'

    # # sc_elasticsearch_host='elasticsearch'
    # SC_HOST = 'elasticsearch'
    # SC_PORT = '9200'
    # SC_INDEX = 'external'
    # SC_TYPE = 'source_package'

    # #store to retrieve features
    # CloudSightStore = Elasticsearch::Client.new(hosts: [{ host: "#{CS_HOST}", port: "#{CS_PORT}" }], log: false)

    # #store to post/pull compliance data
    # SCLocalStore = Elasticsearch::Client.new(hosts: [{ host: "#{SC_HOST}", port: "#{SC_PORT}" }], log: false)

    CS_HOST = 'cloudsight.sl.cloud9.ibm.com'
    CS_PORT = 8885
    CS_ES_HOST = 'elastic2-cs.sl.cloud9.ibm.com'
    CS_ES_PORT = 9200
    CS_ES_MAX_RETURN = 1000
    CloudSightStore = Elasticsearch::Client.new(hosts: [{ host: "#{CS_ES_HOST}", port: "#{CS_ES_PORT}" }], log: false)


    def self.get_containers

    end

    def self.get_images

    end

    def self.get_image_history(image_id)

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

      results.first ? results.first.dockerhistory : nil

    end

    def self.get_container_detail(image_id)

      body = {
        query: {
          bool: {
            must: [
              {
                term: {
                  feature_type: 'dockerinspect'
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
        fields: [ 
          'namespace',
          'dockerinspect.Name',
          'dockerinspect.Image',
          'dockerinspect.Id',
          'dockerinspect.Created',
          'timestamp', 
          '@timestamp'
        ],
        sort: {
          "@timestamp" => {
            order: 'desc'
          }
        },
        size: CS_ES_MAX_RETURN
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
        hit.fields.each_with_object({}) do |(k,v),h|
          h[k] = v.first
        end
      end

    end




    def self.get_vulnerability_scan_results(namespace)
      body = {
        query: {
          bool: {
            must: [
              {
                term: {
                  'namespace.raw' => namespace
                }
              }
            ]
          }
        },
        sort: {
          "timestamp" => {
            order: 'desc'
          }
        },
        size: CS_ES_MAX_RETURN
      }
      opts = {
        index: 'vulnerabilityscan-*',
        type: 'vulnerabilityscan',
        body: body,
        size: CS_ES_MAX_RETURN
      }

      response = Hashie::Mash.new(CloudSightStore.search(opts))
      # results = response.hits.hits.map do |hit|
      #   hit._source
      # end
      results = response.hits.hits

    end

    def self.get_result(request_id)

      body = {
        query: {
          bool: {
            must: [
              # {
              #   term: {
              #     'namespace.raw' => namespace
              #   }
              # }
              {
                term: {
                  'request_id.raw' => request_id
                }
              }
            ]
          }
        },
        size: 1
      }

      opts = {
        index: 'compliance-*',
        type: 'compliance',
        body: body,
        size: 1
      }

      response = Hashie::Mash.new(CloudSightStore.search(opts))
      results = response.hits.hits.map do |hit|
        hit._source.merge({id: hit._id}) 
      end

      results.empty? ? nil : results.first

    end


#     def self.get_results(namespace, key, begin_time=nil, end_time=nil)

#       body = {
#         query: {
#           bool: {
#             must: [
#               {
#                 term: {
#                   namespace: key
#                 }
#               }
#             ]
#           }
#         },
#         sort: {
#           "@timestamp" => {
#             order: 'desc'
#           }
#         },
#         size: CS_ES_MAX_RETURN
#       }

#       range_query_param = {}
#       range_query_param[:gte] = begin_time.utc.iso8601 if begin_time
#       range_query_param[:lte] = end_time.utc.iso8601 if end_time
#       body[:query][:bool][:must] << {range: {'@timestamp' => range_query_param}} unless range_query_param.empty?


#       # index_date = Date.today
#       # index = index_date.strftime("compliance-%Y.%m.%d")   # "compliance-2015.03.25"

#       opts = {
#         index: 'compliance-*',
# #        type: 'logs',
#         type: 'compliance',
#         body: body,
#         size: CS_ES_MAX_RETURN
#       }

#       response = Hashie::Mash.new(CloudSightStore.search(opts))
#       results = response.hits.hits.map do |hit|
#         hit._source
#       end

#       results.select do |r|
#         r.namespace == namespace
#       end


#     end


    def self.crawl_times(namespace, begin_time=nil, end_time=nil)

      current_time = Time.now
      max_days = 60 # days
      begin_time ||= (current_time-max_days*24*60*60)
      end_time ||= current_time

      # res = query "http://#{CS_HOST}:#{CS_PORT}/namespace/crawl_times?namespace=#{namespace}&begin_time=#{begin_time.iso8601(3)}&end_time=#{end_time.iso8601(3)}"
      params = {
        namespace: namespace,
        begin_time: begin_time.iso8601(3),
        end_time: end_time.iso8601(3)
      }
      uri = URI.parse("http://#{CS_HOST}:#{CS_PORT}/namespace/crawl_times")
      uri.query = URI.encode_www_form(params)
      SentinelDocker::Log.debug("calling cloudsight search service api: #{uri.to_s}")
      res = Net::HTTP.get_response(uri)
      body = JSON.parse(res.body)
      body['crawl_times']

    end

    def self.query(uri_string)

      SentinelDocker::Log.debug("calling cloudsight search service api: #{uri_string}")
      uri = URI.parse(uri_string)
      https = Net::HTTP.new(uri.host, uri.port)
      # https.use_ssl = true
      # https.verify_mode = OpenSSL::SSL::VERIFY_NONE
      req = Net::HTTP::Get.new(uri.path)
      # req.basic_auth(token, secret)

      res = https.start do |x|
        x.request(req)
      end

      res

    end

    def self.get_namespaces(begin_time=nil, end_time=nil)

      current_time = Time.now
      max_days = 30 # days
      begin_time ||= (current_time-max_days*24*60*60)
      end_time ||= current_time

      #res = query "http://#{CS_HOST}:#{CS_PORT}/namespaces?begin_time=#{begin_time.iso8601(3)}&end_time=#{end_time.iso8601(3)}"
      params = {
        begin_time: begin_time.iso8601(3),
        end_time: end_time.iso8601(3)
      }
      uri = URI.parse("http://#{CS_HOST}:#{CS_PORT}/namespaces")
      uri.query = URI.encode_www_form(params)

      SentinelDocker::Log.debug("calling cloudsight search service api: #{uri.to_s}")

      res = Net::HTTP.get_response(uri)

      body = JSON.parse(res.body)
      SentinelDocker::Log.debug("response.body=#{body}")
      body['namespaces']

    end

  end
end
