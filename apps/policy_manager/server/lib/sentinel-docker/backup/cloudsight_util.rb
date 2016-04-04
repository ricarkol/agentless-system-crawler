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
  module CloudsightUtil

    # CS_HOST = 'demo3.sl.cloud9.ibm.com'
    # CS_PORT = '9200'
    # CS_INDEX = 'config-2015.02.13'
    # CS_TYPE = 'config_crawler'

    # # sc_elasticsearch_host='elasticsearch'

    # #store to retrieve features
    # CloudSightStore = Elasticsearch::Client.new(hosts: [{ host: "#{CS_HOST}", port: "#{CS_PORT}" }], log: false)

    # #store to post/pull compliance data
    # SCLocalStore = Elasticsearch::Client.new(hosts: [{ host: "#{SC_HOST}", port: "#{SC_PORT}" }], log: false)

    # CS_HOST = 'cloudsight.sl.cloud9.ibm.com'
    # CS_PORT = 8885
    CS_ES_HOST = 'demo3.sl.cloud9.ibm.com'
    # CS_ES_HOST = 'elastic2-cs.sl.cloud9.ibm.com'
    CS_ES_PORT = 9200
    CS_ES_MAX_RETURN = 1000
    CloudSightStore = Elasticsearch::Client.new(hosts: [{ host: "#{CS_ES_HOST}", port: "#{CS_ES_PORT}" }], log: false)

    SC_HOST = 'elasticsearch'
    SC_PORT = '9200'
    SC_CACHE_INDEX = 'sc_cache'
    SC_MAX_RETURN = 1000
    SC_Store = Elasticsearch::Client.new(hosts: [{ host: "#{SC_HOST}", port: "#{SC_PORT}" }], log: false)

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

      SC_Store.indices.put_mapping(
        index: SC_CACHE_INDEX,
        type: type.to_s,
        body: body
      )

      puts "mapping done"

    end

    def self.init

      begin
        SC_Store.indices.create index: SC_CACHE_INDEX
        do_mapping(:result)
        do_mapping(:namespace)
      rescue
        puts "Index <#{SC_CACHE_INDEX}> not created. Already existed."
      end

    end


    # type : snapshot, page, etc.
    def self.put_data_to_cache(type, doc)

      if doc[:id]
        doc.delete[:id]
        result = SC_Store.update(
          index: SC_CACHE_INDEX,
          type: type.to_s,
          id: doc[:id],
          refresh: true,
          body: { doc: doc, doc_as_upsert: true }
        )
      else
        result = SC_Store.index(
          index: SC_CACHE_INDEX,
          type: type.to_s,
          refresh: true,
          body: doc
        )
      end
      doc[:id] = result['_id']

      doc

    end

    def self.get_data_from_cache(type, query)

      param = {
        index: SC_CACHE_INDEX,
        type: type.to_s,
        body: query.merge(size: SC_MAX_RETURN),
      }

      response = Hashie::Mash.new(SC_Store.search(param))
      results = response.hits.hits.map do |hit|
        hit._source.merge(id: hit._id)
      end
      results

    end

    def self.get_namespace_list
      get_namespaces.keys
    end

    def self.get_crawl_times(namespace)
      namespaces = namespace ? get_namespaces : {}
      crawl_times = []
      if namespaces.has_key?(namespace)
        crawl_times = namespaces[namespace][:crawl_times]
      end
      crawl_times.sort
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

      response = Hashie::Mash.new(CloudSightStore.search(opts))
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
      
      namespaces.map do |ns, image|
        Hashie::Mash.new(namespace: ns, crawl_times: image.keys.sort, image: image)
      end

    end

    def self.get_namespaces

      query = {query: {match_all:{}}}
      namespaces = get_data_from_cache(:namespace, query)
      puts "size=#{namespaces.size}"
      if namespaces.empty?
        namespaces = load_namespaces
        namespaces.each do |namespace|
          put_data_to_cache(:namespace, namespace)
        end
      end

      Hash[namespaces.map { |ns| [ns[:namespace], ns] }]


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

      response = Hashie::Mash.new(CloudSightStore.search(opts))
      results = response.hits.hits.map do |hit|
        hit._source.merge(id: hit['_id'])
      end

      Hash[results.map { |r| [r.compliance_id, r] }]

    end

    def self.get_vulnerability_results(namespace, timestamp)

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
                  timestamp: timestamp
                }
              }
            ]
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
      results = response.hits.hits.map do |hit|
        hit._source.merge(id: hit['_id'])
      end

      Hash[results.map { |r| [r.usnid, r] }]

    end

    def self.get_result(namespace, timestamp)

      fail 'namespace and timestamp must be specified' unless namespace && timestamp

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

      results = get_data_from_cache(:result, query)

      # puts "results=#{results.to_json}"

      result = nil

      if results.empty?

        vul_results = get_vulnerability_results(namespace, timestamp)
        comp_results = get_compliance_results(namespace, timestamp)

        vul_false_count = vul_results.values.select { |r| r.vulnerable == false }.size
        vul_total_count = vul_results.size

        comp_false_count = comp_results.values.select { |r| r.compliant == "true" }.size

        result = {
          namespace: namespace,
          crawl_time: timestamp,
          vulnerability: {
            false_count: vul_false_count,
            total_count: vul_total_count,
            overall: "#{vul_total_count-vul_false_count}/#{vul_total_count}"
            # ,results: vul_results
          },
          compliance: {
            overall: comp_false_count == 0 ? 'PASS' : 'FAIL',
            summary: Hash[comp_results.map {|k, v| [k, v.compliant == "true" ? "Pass" : "Fail"]}]
            # ,results: comp_results
          }
        }
        puts "cached : #{namespace}, #{timestamp}"

        result = put_data_to_cache(:result, result)
      else
        puts "cache hit : #{namespace}, #{timestamp}"
        result = results.first
      end

      result

    end

    def self.get_page_per_image(namespace, crawl_time=nil)
      get_vulnerability_results(namespace, timestamp)
    end

    def self.load_results(timestamp)
      #cache namespaces, crawl_time
      #cache result per namespace per crawl_time
      # load all page data since specified timestamp
    end

    def self.get_vulnerability_counts(namespace)

        fail 'namespace must be specified' unless namespace

        crawl_times = get_crawl_times(namespace)

        fail_array = []
        pass_array = []

        crawl_times.sort!

        crawl_times.each do |timestamp|

          snapshot = SentinelDocker::CloudsightUtil.get_result(namespace, timestamp)
          vul_false_count = snapshot[:vulnerability][:false_count] || 0
          vul_total_count = snapshot[:vulnerability][:total_count] || 0

          #timestr = Time.iso8601(timestamp.sub(/(\d)00$/,'\1:00')).strftime("%Y-%m-%d %H:%M:%S")
          timestr = timestamp.sub(/^(\d\d\d\d-\d\d-\d\d)T(\d\d:\d\d:\d\d)[+-]\d\d\d\d$/,'\1 \2')
          fail_array << [timestr, vul_total_count-vul_false_count]
          pass_array << [timestr, vul_false_count]

        end

        [fail_array, pass_array]

    end


    def self.get_vulnerability_page(namespace, timestamp=nil)

        fail 'namespace must be specified' unless namespace

        timestamp ||= get_crawl_times(namespace).first

        fail "no crawl data for <#{namespace}> is found" unless timestamp

        vul_results = get_vulnerability_results(namespace, timestamp)

        vul_false_count = vul_results.values.select { |r| r.vulnerable == false }.size
        vul_total_count = vul_results.size
        usn_ids = vul_results.keys.sort
        vul_table = {}

        vulnerability = usn_ids.map do |usnid| 
          vul = vul_results[usnid]          
          {
            usnid: usnid,
            check: vul.vulnerable ? 'Vulnerable' : 'Safe', 
            description: vul.summary
          }                    
        end

        result = {
          namespace: namespace,
          crawl_time: timestamp,
          overall: "#{vul_total_count-vul_false_count}/#{vul_total_count}",
          vulnerability: vulnerability
        }

    end

    def self.get_result_page_per_namespace(namespace)

      namespaces = SentinelDocker::CloudsightUtil.get_namespaces

      # puts  JSON.pretty_generate(namespaces)

      crawl_times = nil
      image = nil
      if namespaces.has_key?(namespace)
        crawl_times = namespaces[namespace][:crawl_times]
      end

      crawl_times ||= []

      lines = {}
      crawl_times.each do |crawl_time|
        image_conf = namespaces[namespace][:image][crawl_time]
        lines[crawl_time] = SentinelDocker::CloudsightUtil.get_snapshot_row(image_conf)

      end

      lines

    end

    def self.get_snapshot_row(image_conf)
      snapshot = SentinelDocker::CloudsightUtil.get_result(image_conf[:namespace], image_conf[:timestamp])

      row_data = nil

      #      puts "snapshot=#{snapshot.to_json}"

      if snapshot

        row_data = {
          tenant: image_conf[:owner_namespace],
          namespace: image_conf[:namespace],
          crawl_time: image_conf[:timestamp],
          vulnerability: snapshot[:vulnerability][:overall],
          compliance: snapshot[:compliance][:overall],
          results: snapshot[:compliance][:summary]
        }

        #           puts JSON.pretty_generate(row_data)
      end

      row_data

    end

    def self.get_snapshot_page(timestamp)

      namespaces = SentinelDocker::CloudsightUtil.get_namespaces

      # puts  JSON.pretty_generate(namespaces)

      lines = {}
      count = 0
      namespaces.each do |namespace, res|
        crawl_times = res[:crawl_times]
        #        puts "#{namespace}: #{crawl_times}  (#{count}/#{namespaces.keys.size})"
        count += 1

        crawl_time = nil
        crawl_times.each do |t|
          break if t > timestamp
          crawl_time = t
        end

        #        puts "crawl_time: #{crawl_time ? crawl_time : "none"} before :#{timestamp}"

        if crawl_time
          image_conf = res[:image][crawl_time]
          lines[namespace] = SentinelDocker::CloudsightUtil.get_snapshot_row(image_conf)
        end

      end

      lines

    end


    def self.get_rule_descriptions
      
      rule_descriptions = {}
      
      rule_descriptions['Linux.1-1-a'] = <<-EOS
        <font face="Verdana">Each UID must only be used once</font>
      EOS
      
      rule_descriptions['Linux.2-1-c'] = <<-EOS
        <font face="Verdana">One of these two options must be implemented:</font>
        <ul>
        <li type="disc">
        <font face="Verdana">Parameters of "retry=3 minlen=8 dcredit=-1 ucredit=0 lcredit=-1 ocredit=0 type= reject_username" in /etc/pam.d/system-auth to the "password required pam_cracklib.so ..." stanza</font>
        </li>
        <li type="disc">
        <font face="Verdana">parameters of "min=disabled,8,8,8,8 passphrase=0 random=0 enforce=everyone" in /etc/pam.d/system-auth to the "password required pam_passwdqc.so" stanza</font>
        </li>
        </ul>
        <font face="Verdana">
        <br>
        Note: The "type=" parameter to pam_crackllib.so may be omitted if it causes problems.
        <br>
        Note: Use of full path and/or $ISA to pam modules is optional.
        </font>
      EOS

      rule_descriptions['Linux.2-1-d'] = <<-EOS
        <font face="Verdana" color="#0000FF">/etc/login.defs must include this line:</font>
        <br>
        <font face="Verdana">PASS_MIN_DAYS 1</font>
        <br>
        <br>
        <font face="Verdana">Field 4 of /etc/shadow must be 1 for all userids with a password assigned.</font>', 
      EOS
      
      rule_descriptions['Linux.2-1-e'] = <<-EOS
        <font face="Verdana">RedHat Enterprise Linux/RedHat Application Server (any version):</font>
        <br>
        <br>
        <b>
        <font face="Verdana">password $CONTROL pam_unix.so remember=7 use_authtok md5 shadow</font>
        </b>
        <br>
        <ul>
        <li type="disc">
        <font face="Verdana">This statement must appear in /etc/pam.d/system-auth</font>
        </li>
        </ul>
        <br>
        <font face="Verdana">Note: $CONTROL in the following examples must be one of "required", or "sufficient".</font>
        <br>
        <font face="Verdana">Note: Use of full path and/or $ISA to pam modules is optional. </font>
        <br>
        <font face="Verdana">Note: It is acceptable to replace "md5" with "sha512" in the settings above.</font>
        <br>
        <font face="Verdana">Note: For Red Hat Enterprise Linux V6 and later: </font>
        <font face="Verdana" color="#0000FF">T</font>
        <font face="Verdana">his control must ADDITIONALLY be applied to the /etc/pam.d/password-auth file.</font>', 
      EOS
      
      rule_descriptions['Linux.2-1-b'] = <<-EOS
        <font face="Verdana" color="#0000FF">/etc/login.defs must include this line:</font>
        <br>
        <font face="Verdana">PASS_MAX_DAYS 90</font>
        <font face="Verdana">Field 5 of /etc/shadow must be "90"</font>
        <br>------------------------<br>
        <font face="Verdana">Note: This setting in /etc/shadow is not required on userids without a password, <br>
            nor is it required on userids that meet the requirements in "</font>
        <b>
        <font face="Verdana">Exemptions to password rules</font>
        </b>
        <font face="Verdana">"</font>'
      EOS

      rule_descriptions

    end

  end

end

if __FILE__ == $0

  SentinelDocker::CloudsightUtil.init


  # namespaces = SentinelDocker::CloudsightUtil.get_namespaces

  # puts  JSON.pretty_generate(namespaces)

  # namespaces.each do |namespace, res|
  #   res[:crawl_times].each do |timestamp|
  #     snapshot = SentinelDocker::CloudsightUtil.get_result(namespace, timestamp)
  #     # puts JSON.pretty_generate(snapshot)
  #     # vuls = SentinelDocker::CloudsightUtil.get_vulnerability_results(namespace, timestamp)
  #     # puts JSON.pretty_generate(vuls)
  #   end
  # end

  ###########################

  # namespace = 'ns/aaa/cccc'
  # timestamp = Time.now.iso8601
  # query = {
  #   query: {
  #     bool: {
  #       must: [
  #         {
  #           term: {
  #             'namespace' => namespace
  #           }
  #         },
  #         {
  #           term: {
  #             crawl_time: timestamp
  #           }
  #         }
  #       ]
  #     }
  #   }
  # }

  # SentinelDocker::CloudsightUtil.do_mapping(:result)

  # doc = {namespace: namespace, crawl_time: timestamp}

  # results = SentinelDocker::CloudsightUtil.get_data_from_cache(:result, query)
  # puts "query_results=#{results.to_json}"
  # doc_result = SentinelDocker::CloudsightUtil.put_data_to_cache(:result, doc)
  # puts "doc_result=#{doc_result.to_json}"
  # results = SentinelDocker::CloudsightUtil.get_data_from_cache(:result, query)
  # puts "query_results=#{results.to_json}"

  ###########################


  # SentinelDocker::CloudsightUtil.do_mapping(:result)

  # namespaces = SentinelDocker::CloudsightUtil.get_namespaces
  # namespaces.each do |namespace, res|
  #   res[:crawl_times].each do |timestamp|

  #     query = {
  #       query: {
  #         bool: {
  #           must: [
  #             {
  #               term: {
  #                 'namespace' => namespace
  #               }
  #             },
  #             {
  #               term: {
  #                 crawl_time: timestamp
  #               }
  #             }
  #           ]
  #         }
  #       }
  #     }

  #     doc = {namespace: namespace, crawl_time: timestamp}

  #     results = SentinelDocker::CloudsightUtil.get_data_from_cache(:result, query)
  #     puts "query_results=#{results.to_json}"
  #     doc_result = SentinelDocker::CloudsightUtil.put_data_to_cache(:result, doc)
  #     puts "doc_result=#{doc_result.to_json}"
  #     results = SentinelDocker::CloudsightUtil.get_data_from_cache(:result, query)
  #     puts "query_results=#{results.to_json}"

  #     # snapshot = SentinelDocker::CloudsightUtil.get_result(namespace, timestamp)
  #     # puts JSON.pretty_generate(snapshot)
  #     # vuls = SentinelDocker::CloudsightUtil.get_vulnerability_results(namespace, timestamp)
  #     # puts JSON.pretty_generate(vuls)
  #     break
  #   end
  #   break
  # end



  # timestamp = Time.at(Time.now.to_i - 1*24*60*60).iso8601
  # page = SentinelDocker::CloudsightUtil.get_snapshot_page(timestamp)

  # puts JSON.pretty_generate(page)

  namespaces = SentinelDocker::CloudsightUtil.get_namespaces
  namespaces.each do |namespace, res|
    puts "--------------- #{namespace} -----------------"
    page = SentinelDocker::CloudsightUtil.get_result_page_per_namespace(namespace)
    puts JSON.pretty_generate(page)
  end

end


#     def self.get_containers

#     end

#     def self.get_images

#     end

#     def self.get_image_history(image_id)

#       body = {
#         query: {
#           bool: {
#             must: [
#               {
#                 term: {
#                   feature_type: 'dockerhistory'
#                 }
#               },
#               {
#                 term: {
#                   namespace: image_id
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

#       # index_date = Date.today
#       # index = index_date.strftime("compliance-%Y.%m.%d")   # "compliance-2015.03.25"

#       opts = {
#         index: 'config-*',
#         type: 'config_crawler',
#         body: body,
#         size: CS_ES_MAX_RETURN
#       }

#       response = Hashie::Mash.new(CloudSightStore.search(opts))
#       results = response.hits.hits.map do |hit|
#         hit._source
#       end

#       results.first ? results.first.dockerhistory : nil

#     end

#     def self.get_container_detail(image_id)

#       body = {
#         query: {
#           bool: {
#             must: [
#               {
#                 term: {
#                   feature_type: 'dockerinspect'
#                 }
#               },
#               {
#                 term: {
#                   namespace: image_id
#                 }
#               }
#             ]
#           }
#         },
#         fields: [
#           'namespace',
#           'dockerinspect.Name',
#           'dockerinspect.Image',
#           'dockerinspect.Id',
#           'dockerinspect.Created',
#           'timestamp',
#           '@timestamp'
#         ],
#         sort: {
#           "@timestamp" => {
#             order: 'desc'
#           }
#         },
#         size: CS_ES_MAX_RETURN
#       }

#       # index_date = Date.today
#       # index = index_date.strftime("compliance-%Y.%m.%d")   # "compliance-2015.03.25"

#       opts = {
#         index: 'config-*',
#         type: 'config_crawler',
#         body: body,
#         size: CS_ES_MAX_RETURN
#       }

#       response = Hashie::Mash.new(CloudSightStore.search(opts))
#       results = response.hits.hits.map do |hit|
#         hit.fields.each_with_object({}) do |(k,v),h|
#           h[k] = v.first
#         end
#       end

#     end




#     def self.get_vulnerability_scan_results(namespace)
#       body = {
#         query: {
#           bool: {
#             must: [
#               {
#                 term: {
#                   'namespace.raw' => namespace
#                 }
#               }
#             ]
#           }
#         },
#         sort: {
#           "timestamp" => {
#             order: 'desc'
#           }
#         },
#         size: CS_ES_MAX_RETURN
#       }
#       opts = {
#         index: 'vulnerabilityscan-*',
#         type: 'vulnerabilityscan',
#         body: body,
#         size: CS_ES_MAX_RETURN
#       }

#       response = Hashie::Mash.new(CloudSightStore.search(opts))
#       # results = response.hits.hits.map do |hit|
#       #   hit._source
#       # end
#       results = response.hits.hits

#     end

#     def self.get_result(request_id)

#       body = {
#         query: {
#           bool: {
#             must: [
#               # {
#               #   term: {
#               #     'namespace.raw' => namespace
#               #   }
#               # }
#               {
#                 term: {
#                   'request_id.raw' => request_id
#                 }
#               }
#             ]
#           }
#         },
#         size: 1
#       }

#       opts = {
#         index: 'compliance-*',
#         type: 'compliance',
#         body: body,
#         size: 1
#       }

#       response = Hashie::Mash.new(CloudSightStore.search(opts))
#       results = response.hits.hits.map do |hit|
#         hit._source.merge({id: hit._id})
#       end

#       results.empty? ? nil : results.first

#     end


# #     def self.get_results(namespace, key, begin_time=nil, end_time=nil)

# #       body = {
# #         query: {
# #           bool: {
# #             must: [
# #               {
# #                 term: {
# #                   namespace: key
# #                 }
# #               }
# #             ]
# #           }
# #         },
# #         sort: {
# #           "@timestamp" => {
# #             order: 'desc'
# #           }
# #         },
# #         size: CS_ES_MAX_RETURN
# #       }

# #       range_query_param = {}
# #       range_query_param[:gte] = begin_time.utc.iso8601 if begin_time
# #       range_query_param[:lte] = end_time.utc.iso8601 if end_time
# #       body[:query][:bool][:must] << {range: {'@timestamp' => range_query_param}} unless range_query_param.empty?


# #       # index_date = Date.today
# #       # index = index_date.strftime("compliance-%Y.%m.%d")   # "compliance-2015.03.25"

# #       opts = {
# #         index: 'compliance-*',
# # #        type: 'logs',
# #         type: 'compliance',
# #         body: body,
# #         size: CS_ES_MAX_RETURN
# #       }

# #       response = Hashie::Mash.new(CloudSightStore.search(opts))
# #       results = response.hits.hits.map do |hit|
# #         hit._source
# #       end

# #       results.select do |r|
# #         r.namespace == namespace
# #       end


# #     end


#     def self.crawl_times(namespace, begin_time=nil, end_time=nil)

#       current_time = Time.now
#       max_days = 60 # days
#       begin_time ||= (current_time-max_days*24*60*60)
#       end_time ||= current_time

#       # res = query "http://#{CS_HOST}:#{CS_PORT}/namespace/crawl_times?namespace=#{namespace}&begin_time=#{begin_time.iso8601(3)}&end_time=#{end_time.iso8601(3)}"
#       params = {
#         namespace: namespace,
#         begin_time: begin_time.iso8601(3),
#         end_time: end_time.iso8601(3)
#       }
#       uri = URI.parse("http://#{CS_HOST}:#{CS_PORT}/namespace/crawl_times")
#       uri.query = URI.encode_www_form(params)
#       SentinelDocker::Log.debug("calling cloudsight search service api: #{uri.to_s}")
#       res = Net::HTTP.get_response(uri)
#       body = JSON.parse(res.body)
#       body['crawl_times']

#     end

#     def self.query(uri_string)

#       SentinelDocker::Log.debug("calling cloudsight search service api: #{uri_string}")
#       uri = URI.parse(uri_string)
#       https = Net::HTTP.new(uri.host, uri.port)
#       # https.use_ssl = true
#       # https.verify_mode = OpenSSL::SSL::VERIFY_NONE
#       req = Net::HTTP::Get.new(uri.path)
#       # req.basic_auth(token, secret)

#       res = https.start do |x|
#         x.request(req)
#       end

#       res

#     end

#     def self.get_namespaces(begin_time=nil, end_time=nil)

#       current_time = Time.now
#       max_days = 30 # days
#       begin_time ||= (current_time-max_days*24*60*60)
#       end_time ||= current_time

#       #res = query "http://#{CS_HOST}:#{CS_PORT}/namespaces?begin_time=#{begin_time.iso8601(3)}&end_time=#{end_time.iso8601(3)}"
#       params = {
#         begin_time: begin_time.iso8601(3),
#         end_time: end_time.iso8601(3)
#       }
#       uri = URI.parse("http://#{CS_HOST}:#{CS_PORT}/namespaces")
#       uri.query = URI.encode_www_form(params)

#       SentinelDocker::Log.debug("calling cloudsight search service api: #{uri.to_s}")

#       res = Net::HTTP.get_response(uri)

#       body = JSON.parse(res.body)
#       SentinelDocker::Log.debug("response.body=#{body}")
#       body['namespaces']

#     end
