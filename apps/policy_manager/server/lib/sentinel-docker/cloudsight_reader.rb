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
require 'time'

module SentinelDocker
  module CloudsightReader

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

    # CS_HOST = 'demo3.sl.cloud9.ibm.com'
    # CS_PORT = '9200'
    # CS_INDEX = 'config-2015.02.13'
    # CS_TYPE = 'config_crawler'

    # # sc_elasticsearch_host='elasticsearch'

    # #store to retrieve features
    # CS_Store = Elasticsearch::Client.new(hosts: [{ host: "#{CS_HOST}", port: "#{CS_PORT}" }], log: false)

    # #store to post/pull compliance data
    # SCLocalStore = Elasticsearch::Client.new(hosts: [{ host: "#{SC_HOST}", port: "#{SC_PORT}" }], log: false)

    # CS_HOST = 'cloudsight.sl.cloud9.ibm.com'
    # CS_PORT = 8885
    #CS_ES_HOST = 'demo3.sl.cloud9.ibm.com'
    CS_ES_HOST = 'elastic2-cs.sl.cloud9.ibm.com'
    CS_ES_PORT = 9200
    CS_ES_MAX_RETURN = 1000
    SC_HOST = 'elasticsearch'
    SC_PORT = '9200'
    SC_CACHE_INDEX = 'sc_cache'
    SC_MAX_RETURN = 1000


    CS_Store = Elasticsearch::Client.new(hosts: [{ host: "#{CS_ES_HOST}", port: "#{CS_ES_PORT}" }], log: false)
    Cache_Store = Elasticsearch::Client.new(hosts: [{ host: "#{SC_HOST}", port: "#{SC_PORT}" }], log: false)

    def self.init
      begin
        Cache_Store.indices.create index: SC_CACHE_INDEX
        do_mapping(:result)
        do_mapping(:namespace)
        @@init_done = true
      rescue
        puts "Index <#{SC_CACHE_INDEX}> not created. Already existed."
      end
    end

    def self.get_crawl_times_org(image)
      fail "no image specified" unless image
      namespace = image.namespace
      namespaces = namespace ? get_namespaces : {}
      crawl_times = []
      if namespaces.has_key?(namespace)
        crawl_times = namespaces[namespace][:crawl_times]
      end
      crawl_times.sort
    end

    def self.get_crawl_times_by_owner(owner_namespaces)

      return [] unless owner_namespaces && !owner_namespaces.empty? 

      or_cond = {
        should: owner_namespaces.map do |on|
          { 
            term: { 'owner_namespace' => on }
          }     
        end
      }

      query = {
        query: {
          bool: or_cond

        }
      }

      results = get_data_from_cache(:namespace, query)
      Hashie::Mash.new Hash[results.map {|r| [r[:namespace], r[:crawl_times]] }]

    end

    def self.get_crawl_times(image)
      fail "no image specified" unless image
      namespace = image.namespace

      query = {
        query: {
          bool: {
            must: [
              {
                term: {
                  'namespace' => namespace
                }
              }
            ]
          }
        },
        size: 1
      }

      results = get_data_from_cache(:namespace, query)
      results.empty? ? [] : results.first[:crawl_times]

    end


    def self.load_namespaces

      body = {
        query:{
          bool: {
            must: [
              {
                term: {
                  "feature_type.raw" => "dockerinspect"
                }
              },
              {
                range: {
                  timestamp: {
                    gte: 1432615555158
                  }
                }
              }
            ]
          }
        },
        fields: [
          'container_long_id',
          'timestamp',
          'owner_namespace',
          'system_type',
          'container_name',
          'container_image',
          'namespace'
        ],
        size: CS_ES_MAX_RETURN
      }

      opts = {
        index: 'config-*',
        type: 'config_crawler',
        body: body,
        size: CS_ES_MAX_RETURN
      }

      response = Hashie::Mash.new(CS_Store.search(opts))
      results = response.hits.hits.map do |hit|
        res = hit.fields != nil ? hit.fields.merge(id: hit['_id']) : {}
        res = res.map { |k,v| [k, v.kind_of?(Array) ? v.first : v] }
        Hashie::Mash.new Hash[res]
      end

      namespaces = {}
      results.each do |result|
        image = (namespaces.has_key? result.namespace) ? namespaces[result.namespace] : Hashie::Mash.new
        image[result.timestamp] = result
        namespaces[result.namespace] = image
      end
      
      # namespaces : {namespace => image}
      # image : {crawl_time => result}
      # result : {
      #       'container_long_id',
      #       'timestamp',
      #       'owner_namespace',
      #       'system_type',
      #       'container_name',
      #       'container_image',
      #       'namespace'
      #       }

      namespaces.map do |ns, image|
        owner_namespace = image.values.first['owner_namespace']
        puts "namespace=#{ns}, owner_namespace=#{owner_namespace}"
        Hashie::Mash.new(namespace: ns, owner_namespace: owner_namespace, crawl_times: image.keys.sort, image: image)
      end

    end

    def self.update_namespaces
      registered_namespaces = get_namespaces
      namespaces = load_namespaces
      namespaces.each do |namespace|
        put_data_to_cache(:namespace, namespace) unless registered_namespaces.include? namespace
      end
    end

    def self.get_namespaces
      query = {query: {match_all:{}}}
      namespaces = get_data_from_cache(:namespace, query)
      Hash[namespaces.map { |ns| [ns[:namespace], ns] }]
    end

    def self.get_results_by_owner(owner_namespaces) 

      return [] unless owner_namespaces && !owner_namespaces.empty? 

      or_cond = {
        should: owner_namespaces.map do |on|
          { 
            term: { 'owner_namespace' => on }
          }     
        end
      }

      query = {
        query: {
          bool: or_cond
        },
        size: 0,
        aggs: {
          results: {
            terms: {
              'field' => 'namespace',
              'size' => SC_MAX_RETURN
            },
            aggs: {
              top: {
                top_hits: {
                  sort: [
                    {
                      'crawl_time' => {
                        'order' => 'desc'
                      }
                    }
                  ],
                  from: 0,
                  size: 1
                }
              }
            }
          }
        }
      }

      t1 = Time.now.usec

      results = get_data_array_from_cache(:result, query)

      puts "----------------------------------"
      puts "response=#{JSON.pretty_generate(results)}"
      puts "----------------------------------"



      # puts "time to load from cache : #{Time.now.usec - t1}"

      Hashie::Mash.new Hash[results.map {|r| [r[:namespace], r] } ]

    end


    def self.get_result(image, timestamp)

      fail 'image and timestamp must be specified' unless image && timestamp

      namespace = image.namespace

      query = {
        query: {
          bool: {
            must: [
              {
                term: {
                  'namespace' => namespace
                }
              },
              {
                term: {
                  crawl_time: timestamp
                }
              }
            ]
          }
        }
      }

      t1 = Time.now.usec

      results = get_data_from_cache(:result, query)

      # puts "time to load from cache : #{Time.now.usec - t1}"

      # puts "results=#{results.to_json}"

      result = nil

      if results.empty?

        vul_overall = get_vulnerability_overall(namespace)

        comp_results = get_compliance_results(namespace, timestamp)
        comp_false_count = comp_results.values.select { |r| r.compliant == "true" }.size

        # puts "comp_results=#{comp_results}"

        result = {
          namespace: namespace,
          owner_namespace: image.owner_namespace,
          crawl_time: timestamp,
          vulnerability: vul_overall,
          compliance: {
            overall: comp_false_count == 0 ? 'PASS' : 'FAIL',
            summary: Hash[comp_results.map {|k, v| [k, 
              {
                result: (v.compliant == "true" ? "Pass" : "Fail"),
                description: v.description, 
                reason: v.reason
              }
            ]}]
            # ,results: comp_results
          }
        }
        puts "cached : #{namespace}, #{timestamp}"

        result = put_data_to_cache(:result, result)
      else
#        puts "cache hit : #{namespace}, #{timestamp}"
        result = results.first
      end

      result

    end

    # def self.get_compliance_results(namespace, timestamp)

    #   body = {
    #     query:{
    #       bool: {
    #         must: [
    #           {
    #             term: {
    #               'namespace.raw' => namespace
    #             }
    #           },
    #           {
    #             term: {
    #               crawled_time: timestamp
    #             }
    #           }
    #         ]
    #       }
    #     },
    #     size: CS_ES_MAX_RETURN
    #   }


    #   opts = {
    #     index: 'compliance-*',
    #     type: 'compliance',
    #     body: body,
    #     size: CS_ES_MAX_RETURN
    #   }

    #   response = Hashie::Mash.new(CS_Store.search(opts))
    #   results = response.hits.hits.map do |hit|
    #     hit._source.merge(id: hit['_id'])
    #   end

    #   Hash[results.map { |r| [r.compliance_id, r] }]

    # end

    def self.get_compliance_results(namespace, crawled_time)

      body = {
        query: {
          bool:{
            must: [
              { 
                match_phrase_prefix: {
                  'namespace.raw' => namespace
                }
              },
              {
                match: {
                  crawled_time: crawled_time
                }
              }
            ]
          }
        },
        size: 100
      }

      opts = {
        index: 'compliance-*',
        type: 'compliance',
        body: body,
        size: CS_ES_MAX_RETURN
      }

      response = Hashie::Mash.new(CS_Store.search(opts))
      results = response.hits.hits.map do |hit|
        hit._source.merge(id: hit['_id'])
      end

      Hash[results.map { |r| [r.compliance_id, r] }]


    end

    def self.get_vulnerability_results(image, timestamp)

      body = {
        query: { 
          filtered: { 
            filter: { 
              exists: { field: 'package_name' }
            },
            query: {
              bool: {
                must: [
                  {
                    match_phrase_prefix: {
                      'namespace.raw' => image.namespace
                    }
                  },
                  {
                    match: {
                      'timestamp' => timestamp
                    }
                  }
                ]
              }
            }
          }
        }
      }

      opts = {
        index: 'vulnerabilityscan-*',
        type: 'vulnerabilityscan',
        body: body,
        size: 1000
      }

      response = Hashie::Mash.new(CS_Store.search(opts))
      results = response.hits.hits.map do |hit|
        hit._source.merge(id: hit['_id'])
      end

      Hash[results.map { |r| [r.package_name, r] }]

    end


    def self.get_vulnerability_overall(namespace)

      body = {
        query: {
          bool:{
            must: [
              {
                match_phrase_prefix: {
                  'namespace.raw' => namespace
                }
              },
              {
                match_phrase_prefix: {
                  description: 'Overall vulnerability status'
                }
              }
            ]
          }
        },
        sort: [ 
          { '@timestamp' => { 'order' => 'desc', 'ignore_unmapped' => true } }
        ]        
      }

      opts = {
        index: 'vulnerabilityscan-*',
        type: 'vulnerabilityscan',
        body: body,
        size: 1, 
      }

      response = Hashie::Mash.new(CS_Store.search(opts))
      hit = response.hits.hits.first
      hit ? hit._source.merge(id: hit['_id']) : nil

    end


    def self.get_compliance_results(namespace, timestamp)

      body = {
        query:{
          bool: {
            must: [
              {
                term: {
                  'namespace.raw' => namespace
                }
              },
              {
                term: {
                  crawled_time: timestamp
                }
              }
            ]
          }
        },
        size: CS_ES_MAX_RETURN
      }


      opts = {
        index: 'compliance-*',
        type: 'compliance',
        body: body,
        size: CS_ES_MAX_RETURN
      }

      response = Hashie::Mash.new(CS_Store.search(opts))
      results = response.hits.hits.map do |hit|
        hit._source.merge(id: hit['_id'])
      end

      Hash[results.map { |r| [r.compliance_id, r] }]

    end

    # def self.get_vulnerability_results(namespace, timestamp)

    #   body = {
    #     query:{
    #       bool: {
    #         must: [
    #           {
    #             term: {
    #               'namespace.raw' => namespace
    #             }
    #           },
    #           {
    #             term: {
    #               timestamp: timestamp
    #             }
    #           }
    #         ]
    #       }
    #     },
    #     size: CS_ES_MAX_RETURN
    #   }


    #   opts = {
    #     index: 'vulnerabilityscan-*',
    #     type: 'vulnerabilityscan',
    #     body: body,
    #     size: CS_ES_MAX_RETURN
    #   }

    #   response = Hashie::Mash.new(CS_Store.search(opts))
    #   results = response.hits.hits.map do |hit|
    #     hit._source.merge(id: hit['_id'])
    #   end

    #   Hash[results.map { |r| [r.usnid, r] }]

    # end

    private

    def self.do_mapping(type)

      body = {
        "#{type.to_s}" => {
          '_timestamp' => {
            'enabled' => true, 'store' => true
          },
          'dynamic_templates' => [
            {
              'strings_not_analyzed' => {
                'match' => '*',
                'match_mapping_type' => 'string',
                'mapping' => {
                  'type' => 'string',
                  'index' => 'not_analyzed'
                }
              }
            }
          ]
        }
      }

      Cache_Store.indices.put_mapping(
        index: SC_CACHE_INDEX,
        type: type.to_s,
        body: body
      )

      puts "mapping done"

    end

    def self.get_raw_data_from_cache(type, query)




    end

    def self.get_data_array_from_cache(type, query)

      param = {
        index: SC_CACHE_INDEX,
        type: type.to_s,
        body: query
      }

      response = nil
      begin
        response = Hashie::Mash.new(Cache_Store.search(param))
      rescue Elasticsearch::Transport::Transport::Error
      end

      results = []
      if response 
        results = response.aggregations.results.buckets.map do |bucket|
          hit = bucket.top.hits.hits.first
          hit._source.merge(id: hit._id)
        end
      end

      results

    end



    def self.get_data_from_cache(type, query)

      param = {
        index: SC_CACHE_INDEX,
        type: type.to_s,
        body: query.merge(size: SC_MAX_RETURN),
      }

      response = nil
      begin
        response = Hashie::Mash.new(Cache_Store.search(param))
      rescue Elasticsearch::Transport::Transport::Error
      end

      results = []
      if response 
        results = response.hits.hits.map do |hit|
          hit._source.merge(id: hit._id)
        end
      end
      results

    end

    # type : snapshot, page, etc.
    def self.put_data_to_cache(type, doc)

      if doc[:id]
        doc.delete[:id]
        result = Cache_Store.update(
          index: SC_CACHE_INDEX,
          type: type.to_s,
          id: doc[:id],
          refresh: true,
          body: { doc: doc, doc_as_upsert: true }
        )
      else
        result = Cache_Store.index(
          index: SC_CACHE_INDEX,
          type: type.to_s,
          refresh: true,
          body: doc
        )
      end
      doc[:id] = result['_id']

      doc

    end

  end

end

if __FILE__ == $0



  SentinelDocker::CloudsightReader.init
  # (0...100).each do |i|

  #   t = Time.now.usec
  #   puts "i=#{i}"
  #   namespaces = SentinelDocker::CloudsightReader.get_namespaces
  #   puts "t=#{Time.now.usec - t}"

  # end


  # namespaces.each do |namespace, res|
  #   puts "--------------- #{namespace} -----------------"
  #   crawl_times = res[:crawl_times] || []
  #   crawl_times.each do |crawl_time|
  #     snapshot = SentinelDocker::CloudsightReader.get_result(namespace, crawl_time)
  #   end
  # end

  # namespace = 'secreg2.sl.cloud9.ibm.com:5000/cloudsight/kelk-elasticsearch:latest'
  # timestamp = '2015-07-17T18:49:51-0500'

  # puts "calling get_vulnerabilities ..."
  # results = SentinelDocker::CloudsightReader.get_vulnerability_results(namespace, timestamp)
  # puts "response=#{JSON.pretty_generate(results)}"

  # puts "calling get_vulnerability_overall ..."
  # result = SentinelDocker::CloudsightReader.get_vulnerability_overall(namespace)
  # puts "response=#{JSON.pretty_generate(result)}"


  # SentinelDocker::CloudsightReader.get_namespaces.keys.each do |namespace|
  #   if namespace && md = namespace.match(/^(\S+)\/(\S+)\/(\S+)\:(\S+)$/)
  #     puts "namespace  : #{md[0]}"
  #     puts "regsitry   : #{md[1]}"
  #     puts "image_name : #{md[3]}"
  #     puts "tag        : #{md[4]}"
  #   else
  #     puts "unmathced  : #{namespace}"
  #   end
  # end



  # puts "calling get_compliance_results ..."
  # result = SentinelDocker::CloudsightReader.get_compliance_results(namespace, timestamp)
  # puts "response=#{JSON.pretty_generate(result)}"

end
