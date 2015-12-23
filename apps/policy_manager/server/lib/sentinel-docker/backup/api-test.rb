# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
require 'grape-swagger'
require 'sentinel-docker/grape_monkey_patch'

module SentinelDocker
  module Container
    DESCRIPTIONS = {
      api_key: 'User\'s api key for programmatic API access',
      openid: 'User\'s OpenID realm URI or identity URI used to authenticate'\
              '  the user for interactive access to the application.'
    }
    PAGE_OPTS = {
      headers: {
        'Range' => {
          required: false,
          description: 'Range of items to return. '\
                       "Default is 'items=1-#{SentinelDocker::Config.db.limit}'"
        }
      },
      http_codes: {
        200 => 'Success. Complete response.',
        206 => 'Success. Partial content.'
      },
      notes: 'Response headers: <br/><b>Content-Range</b> header indicating the range'\
             ' being returned and the total. (e.g. <em>Content-Range: items n-m/total</em>)'
    }

    class Root
      def self.call(env)
        [200, {'Content-Type' => 'text/plain'}, ['Hello']]
      end
    end

    class Root2 < Grape::API
      format :json
      default_format :json

      logger SentinelDocker::Log

      helpers do
        def log
          SentinelDocker::Log
        end

        def session
          env['rack.session']
        end

        def current_user
          return @current_user if @current_user
          if session && session['identity']
            @current_user = Models::User.find(query: { identity: session['identity'] }).first
          elsif params[:api_key]
            @current_user = Models::User.find(query: { api_key: params[:api_key] }).first
          end
          @current_user
        end

        def range(h)
          opts = { offset: 0, limit: SentinelDocker::Config.db.limit }
          h = h['Range']
          unless h.nil?
            h = h.split('=')
            if h.size == 2
              h = h.last.split('-')
              opts[:offset] = [h[0].to_i - 1, 0].max unless h[0].nil?
              opts[:limit] = h[1].to_i - opts[:offset] unless h[1].nil?
            end
          end
          opts
        end

        def set_page(items) # rubocop:disable AccessorMethodName
          header(
            'Content-Range',
            "items #{items.offset + 1}-#{[items.offset + items.limit, items.total].min}"\
                  "/#{items.total}"
          )
          status 206 if items.total > items.size
          items
        end

        def error_out(code, ex = nil)
          reason = params['route_info'].route_http_codes[code]
          reason = "#{reason} #{ex}" unless ex.nil?
          error!(reason, code)
        end
      end

      require 'sentinel-docker/api/container_groups'
      require 'sentinel-docker/api/container_rules'
      require 'sentinel-docker/api/containers'
      require 'sentinel-docker/api/images'
      require 'sentinel-docker/api/rule_groups'
      require 'sentinel-docker/api/rules'
      require 'sentinel-docker/api/configuration'
      require 'sentinel-docker/api/users'
      require 'sentinel-docker/api/about'

      mount SentinelDocker::API::ContainerGroups
      mount SentinelDocker::API::Containers
      mount SentinelDocker::API::Images
      mount SentinelDocker::API::RuleGroups
      mount SentinelDocker::API::Rules
      mount SentinelDocker::API::Configuration
      mount SentinelDocker::API::Users
      mount SentinelDocker::API::About

#      mount SentinelDocker::API::SystemGroups
#      mount SentinelDocker::API::Systems
#      mount SentinelDocker::API::CandidateSystems
#      mount SentinelDocker::API::PolicyGroups
#      mount SentinelDocker::API::Policies
#      mount SentinelDocker::API::Configuration
#      mount SentinelDocker::API::Users
#      mount SentinelDocker::API::About

      add_swagger_documentation(
        hide_documentation_path: true,
        hide_format: true,
        info: {
          title: 'Security & Compliance for Docker Cloud',
          description: 'Operational Security Compliance Monitoring as a service.'
        },
        mount_path: 'api/docs'
      )
    end
  end
end

require 'sentinel-docker/api/openid'
