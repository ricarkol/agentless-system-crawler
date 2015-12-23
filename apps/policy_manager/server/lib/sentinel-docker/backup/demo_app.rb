# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
# require 'json'
# require 'logger'


require 'rack/request'
require 'rack/session/cookie'

require 'scdocker_utils'
require 'port_vul'
require 'sentinel-docker/configuration'
require 'sentinel-docker/docker_util'
require 'sentinel-docker/search_api'
require 'sentinel-docker/cloudsight_util'

module SentinelDocker
  module Container
#     class PortVulView
#       def self.call(env)

#         containers = ScdockerUtils.find_containers
#         containers.each do |container|
#           scan_result=PortVul.check(container.id)
#           container[:scan_result]=scan_result
#         end
#         page = PortVul.getHTML(containers)
#         [200, {'Content-Type' => 'text/html'}, [page]]

#       end
#     end

#     class ContainerHistoryView
#       def self.call(env)

#         req=::Rack::Request.new(env)
#         params = req.params
         
# #        params={}
# #        params["image_id"] = "f5e68a7ab7969aaded84d762922407e9e5420218f964133339b0f0215b9f973f"
# #        params["key"] = "openjdk-7"
#         page = ScdockerUtils::HistoryView.getHistoryView(params["image_id"], params["key"])
# #         page = params.to_s
#         page ||= {}
#         [200, {'Content-Type' => 'text/html'}, [page]]
#       end
#     end

    # class ImageHistoryView
    #   def self.call(env)
    #   	params={}
    #     params["image_id"] = "ce2c0f4153252ce16bfe16225dbfb127b53505509237b1ae272b8d09761a51f0"
    #     page = ScdockerUtils::ImageHistoryView.getImageHistoryGraph(params["image_id"])
    #     page ||= {}
    #     [200, {'Content-Type' => 'text/html'}, [page]]

    #   end
    # end

    # class ImageHistoryView
    #   def self.call(env)
    #     page = `cd /opt/ibm/sentinel; bundle exec ruby lib/sentinel-docker/image_history_view.rb`
    #     page ||= {}
    #     [200, {'Content-Type' => 'text/html'}, [page]]
    #   end
    # end


    # class StatusView
    #   def self.call(env)
    #     page = SentinelDocker::DockerUtil.get_report('status_report', false)
    #     page ||= {}
    #     [200, {'Content-Type' => 'text/html'}, [page]]
    #   end
    # end

    # class VulnerabilityView
    #   def self.call(env)
    #     page = SentinelDocker::DockerUtil.get_report('vulnerability_report', false)
    #     page ||= {}
    #     [200, {'Content-Type' => 'text/html'}, [page]]
    #   end
    # end

    # class GetReportData
    #   def self.call(env)
    #     data = SentinelDocker::SearchAPI.get_data
    #     page = data ? JSON.pretty_generate(data) : {}
    #     [200, {'Content-Type' => 'application/json'}, [page]]
    #   end
    # end

    class GetRules
      def self.call(env)
        SentinelDocker::Log.debug "get_rules are called"
        req=::Rack::Request.new(env)
        params = req.params
        SentinelDocker::Log.debug "params=#{params}"
        data = SentinelDocker::SearchAPI.get_rules(params["namespace"], params["owner_namespace"])
        puts "data=#{data}"
        page = data ? JSON.pretty_generate(data) : {}
        [200, {'Content-Type' => 'application/json'}, [page]]
      end      
    end

    class GetRulesPerTenant
      def self.call(env)
        SentinelDocker::Log.debug "get_rules_per_tenant are called"
        req=::Rack::Request.new(env)
        params = req.params
        SentinelDocker::Log.debug "params=#{params}"
        data = SentinelDocker::SearchAPI.get_rules_per_tenant(params["tenant"])
        puts "data=#{data}"
        page = data ? JSON.pretty_generate(data) : {}
        [200, {'Content-Type' => 'application/json'}, [page]]
      end      
    end

    class GetImageStatusPerTenant
      def self.call(env)
        SentinelDocker::Log.debug "get_image_status_per_tenant are called"
        req=::Rack::Request.new(env)
        params = req.params
        SentinelDocker::Log.debug "params=#{params}"
        data = SentinelDocker::SearchAPI.get_image_status_per_tenant(params["tenant"])
        puts "data=#{data}"
        page = data ? JSON.pretty_generate(data) : {}
        [200, {'Content-Type' => 'application/json'}, [page]]
      end      
    end

    class GetRuleAssignGroups
      def self.call(env)
        SentinelDocker::Log.debug "get_rule_assign_groups are called"
        req=::Rack::Request.new(env)
        params = req.params
        SentinelDocker::Log.debug "params=#{params}"
        data = SentinelDocker::SearchAPI.get_rule_assign_groups(params["tenant"])
        puts "data=#{data}"
        page = data ? JSON.pretty_generate(data) : {}
        [200, {'Content-Type' => 'application/json'}, [page]]
      end      
    end

    class GetTenantRules
      def self.call(env)
        SentinelDocker::Log.debug "get_tenant_rules are called"
        req=::Rack::Request.new(env)
        params = req.params
        SentinelDocker::Log.debug "params=#{params}"
        data = SentinelDocker::SearchAPI.get_tenant_rules(params["tenant"], params["group"])
        puts "data=#{data}"
        page = data ? JSON.pretty_generate(data) : {}
        [200, {'Content-Type' => 'application/json'}, [page]]
      end      
    end

    class SetTenantRules
      def self.call(env)
        SentinelDocker::Log.debug "set_tenant_rules are called"
        req=::Rack::Request.new(env)
        conf = req.body.read
        params = req.params
        SentinelDocker::Log.debug "params=#{params}, conf=#{conf}"
        SentinelDocker::SearchAPI.set_tenant_rules(params["tenant"], params["group"], conf, params["default"])
        page = ""
        [200, {'Content-Type' => 'application/json'}, [page]]
      end      
    end

    class GetSnapshotPage
      def self.call(env)
        SentinelDocker::Log.debug "get_snapshot_page is called"
        req=::Rack::Request.new(env)
        params = req.params
        SentinelDocker::Log.debug "params=#{params}"
        data = SentinelDocker::CloudsightUtil.get_snapshot_page(params["timestamp"])
        page = data ? JSON.pretty_generate(data) : {}
        [200, {'Content-Type' => 'application/json'}, [page]]
      end      
    end

    class GetResult
      def self.call(env)
        SentinelDocker::Log.debug "get_result is called"
        req=::Rack::Request.new(env)
        params = req.params
        SentinelDocker::Log.debug "params=#{params}"
        data = SentinelDocker::CloudsightUtil.get_result(params["namespace"], params["timestamp"])
        page = data ? JSON.pretty_generate(data) : {}
        [200, {'Content-Type' => 'application/json'}, [page]]
      end      
    end

    class SetNamespacesToGroup
      def self.call(env)
        SentinelDocker::Log.debug "set_namespaces_to_group are called"
        req=::Rack::Request.new(env)
        conf = req.body.read
        params = req.params
        SentinelDocker::Log.debug "params=#{params}, conf=#{conf}"
        SentinelDocker::SearchAPI.set_namespaces_to_group(params["tenant"], params["group"], conf)
        page = ""
        [200, {'Content-Type' => 'application/json'}, [page]]
      end      
    end


    class GetNamespaces
      def self.call(env)
        SentinelDocker::Log.debug "get_namespaces is called"
        req=::Rack::Request.new(env)
        data = SentinelDocker::CloudsightUtil.get_namespaces
        page = data ? JSON.pretty_generate(data) : {}
        [200, {'Content-Type' => 'application/json'}, [page]]
      end      
    end

    class GetNamespaceList
      def self.call(env)
        SentinelDocker::Log.debug "get_namespace_list is called"
        req=::Rack::Request.new(env)
        data = SentinelDocker::CloudsightUtil.get_namespace_list
        page = data ? JSON.pretty_generate(data) : {}
        [200, {'Content-Type' => 'application/json'}, [page]]
      end      
    end

    class GetCrawlTimes
      def self.call(env)
        SentinelDocker::Log.debug "get_crawl_times is called"
        req=::Rack::Request.new(env)
        params = req.params
        SentinelDocker::Log.debug "params=#{params}"
        data = SentinelDocker::CloudsightUtil.get_crawl_times(params["namespace"])
        page = data ? JSON.pretty_generate(data) : {}
        [200, {'Content-Type' => 'application/json'}, [page]]
      end      
    end

    class GetResultPagePerNamespace
      def self.call(env)
        SentinelDocker::Log.debug "get_result_page_per_namespace is called"
        req=::Rack::Request.new(env)
        params = req.params
        SentinelDocker::Log.debug "params=#{params}"
        data = SentinelDocker::CloudsightUtil.get_result_page_per_namespace(params["namespace"])
        page = data ? JSON.pretty_generate(data) : {}
        [200, {'Content-Type' => 'application/json'}, [page]]
      end      
    end

    class GetVulnerabilityPage
      def self.call(env)
        SentinelDocker::Log.debug "get_vulnerability_page is called"
        req=::Rack::Request.new(env)
        params = req.params
        SentinelDocker::Log.debug "params=#{params}"
        data = SentinelDocker::CloudsightUtil.get_vulnerability_page(params["namespace"], params["timestamp"])
        page = data ? JSON.pretty_generate(data) : {}
        [200, {'Content-Type' => 'application/json'}, [page]]
      end      
    end

    class GetVulnerabilityCounts
      def self.call(env)
        SentinelDocker::Log.debug "get_vulnerability_counts is called"
        req=::Rack::Request.new(env)
        params = req.params
        SentinelDocker::Log.debug "params=#{params}"
        data = SentinelDocker::CloudsightUtil.get_vulnerability_counts(params["namespace"])
        page = data ? JSON.pretty_generate(data) : {}
        [200, {'Content-Type' => 'application/json'}, [page]]
      end      
    end

    class GetRuleDescriptions
      def self.call(env)
        SentinelDocker::Log.debug "get_rule_descriptions is called"
        req=::Rack::Request.new(env)
        data = SentinelDocker::CloudsightUtil.get_rule_descriptions
        page = data ? JSON.pretty_generate(data) : {}
        [200, {'Content-Type' => 'application/json'}, [page]]
      end      
    end


  end
end
