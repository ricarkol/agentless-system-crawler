# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
module SentinelDocker
  module API
    class Services < Grape::API

      DESCRIPTIONS = ::SentinelDocker::API::DESCRIPTIONS
      ServiceUtils = SentinelDocker::ServiceUtils
      Log = SentinelDocker::Log
      
      prefix 'api'
      format :json
      default_format :json

      params do
        optional :api_key, type: String, param_type: 'query',
          desc: DESCRIPTIONS[:api_key]
        optional :openid, type: String, param_type: 'query',
          desc: DESCRIPTIONS[:openid]
        optional :tenant, type: String, param_type: 'query', 
          desc: DESCRIPTIONS[:tenant]
      end

      resource :services, desc: 'Service APIs' do

        # GET /get_rules
        desc 'do_nothing', http_codes: {
          200 => 'Success'
        }
        params do
          optional :dummy, type: String, param_type: 'query',
            desc: 'dummy'
        end
        get 'do_nothing' do
          Log.debug "do_nothing are called : params=#{params}"
          user = current_user || {}
          tenant = target_tenant || {}
          {current_user: user.serializable_hash(only: [:tenant_id, :identity, :id, :full_name, :email, :timestamp]), tenant: tenant}
        end

        #called from compliance annotator only
        # GET /get_rules
        desc 'get_rules', http_codes: {
          200 => 'Success'
        }
        params do
          requires :namespace, type: String, param_type: 'query',
            desc: 'namespace'
          requires :owner_namespace, type: String,  param_type: 'query',
            desc: 'owner_namespace'
        end
        get 'get_rules' do
          Log.debug "get_rules are called : params=#{params}"
          data = ServiceUtils.get_rules(params["namespace"], params["owner_namespace"])
        end

        # GET /get_rules_per_tenant
        desc 'get_rules_per_tenant', http_codes: {
          200 => 'Success'
        }
        get 'get_rules_per_tenant' do          
          Log.debug "get_rules_per_tenant are called: params=#{params}"
          data = ServiceUtils.get_rules_per_tenant(target_tenant)
        end

        # GET /get_image_status_per_tenant
        desc 'get_image_status_per_tenant', http_codes: {
          200 => 'Success'
        }
        get 'get_image_status_per_tenant' do
          Log.debug "get_image_status_per_tenant are called: params=#{params}"
          data = ServiceUtils.get_image_status_per_tenant(target_tenant)
        end

        # GET /get_groups
        desc 'get_groups', http_codes: {
          200 => 'Success'
        }
        get 'get_groups' do
          Log.debug "get_groups are called: params=#{params}"
          data = ServiceUtils.get_groups(target_tenant)
        end

        # GET /get_tenant_rules
        desc 'get_tenant_rules', http_codes: {
          200 => 'Success'
        }
        params do
          optional :group, type: String, param_type: 'query',
            desc: 'group id'
        end
        get 'get_tenant_rules' do
          Log.debug "get_tenant_rules are called: params=#{params}"
          data = ServiceUtils.get_tenant_rules(target_tenant, params["group"])
        end

        # PUT /set_namespaces_to_group
        desc 'set_namespaces_to_group', http_codes: {
          200 => 'Success',
          400 => 'Bad request. Check request body.'
        }
        params do
          requires :body, type: Array, desc: 'json array of namespaces', presence: false
          requires :group, type: String, param_type: 'query',
            desc: 'group id'
        end
        put 'set_namespaces_to_group' do
          Log.debug "set_namespaces_to_group are called"
          error_out(400, "body=#{env['api.request.body']}") unless env['api.request.body'].is_a?(Array)
          conf = env['api.request.body']
          Log.debug "params=#{params}, conf=#{conf}"
          ServiceUtils.set_namespaces_to_group(target_tenant, params["group"], conf, is_admin)
          ''
        end

        # PUT /set_tenant_rules
        desc 'set_tenant_rules', http_codes: {
          200 => 'Success',
          400 => 'Bad request. Check request body.'
        }
        params do
          requires :body, type: Array, desc: 'a list of rule ids', presence: false
          requires :group, type: String, param_type: 'query',
            desc: 'group id'
          optional :default, type: Boolean, param_type: 'query',
            desc: 'default', default: false
        end
        put 'set_tenant_rules' do
          Log.debug "set_tenant_rules are called"
          error_out(400, "body=#{env['api.request.body']}") unless env['api.request.body'].is_a?(Array)
          body = env['api.request.body']
          Log.debug "params=#{params}, body=#{body}"
          ServiceUtils.set_tenant_rules(target_tenant, params["group"], body, params["default"])
          ''
        end

        # GET /get_auto_assign
        desc 'get_auto_assign', http_codes: {
          200 => 'Success',
        }
        params do
          requires :group, type: String, param_type: 'query',
            desc: 'group id'
        end
        get 'get_auto_assign' do
          Log.debug "get_auto_assign are called: params=#{params}"
          ServiceUtils.get_auto_assign(target_tenant, params["group"])
        end


        # PUT /set_auto_assign
        desc 'set_auto_assign', http_codes: {
          200 => 'Success',
          400 => 'Bad request. Check request body.'
        }
        params do
          requires :body, type: Object, desc: 'auto assign configuration (JSON-formatted)', presence: false
          requires :group, type: String, param_type: 'query',
            desc: 'group id'
        end
        put 'set_auto_assign' do
          Log.debug "set_auto_assign are called"
          body = env['api.request.body']
          Log.debug "params=#{params}, body=#{body}"
          ServiceUtils.set_auto_assign(target_tenant, params["group"], body)
          ''
        end

        # GET /get_result_page
        desc 'get_result_page', http_codes: {
          200 => 'Success'
        }
        get 'get_result_page' do
          Log.debug "get_result_page is called: params=#{params}"
          data = ServiceUtils.get_result_page(target_tenant)
        end

        # GET /get_result
        desc 'get_result', http_codes: {
          200 => 'Success'
        }
        params do
          requires :namespace, type: String, param_type: 'query',
            desc: 'namespace'
          requires :timestamp, type: String, param_type: 'query',
            desc: 'timestamp'
        end
        get 'get_result' do
          Log.debug "get_result is called: params=#{params}"
          data = ServiceUtils.get_result(target_tenant, params["namespace"], params["timestamp"])
        end

        # # GET /get_namespaces
        # desc 'get_namespaces', http_codes: {
        #   200 => 'Success'
        # }
        # get 'get_namespaces' do
        #   Log.debug "get_namespaces is called"
        #   data = ServiceUtils.get_namespaces(target_tenant)
        # end

        # GET /get_namespace_list
        desc 'get_namespaces', http_codes: {
          200 => 'Success'
        }
        get 'get_namespaces' do
          Log.debug "get_namespaces is called"
          data = ServiceUtils.get_namespaces(target_tenant)
        end

        # GET /get_crawl_times
        desc 'get_crawl_times', http_codes: {
          200 => 'Success'
        }
        params do
          requires :namespace, type: String, param_type: 'query',
            desc: 'namespace'
        end
        get 'get_crawl_times' do
          Log.debug "get_crawl_times is called: params=#{params}"
          data = ServiceUtils.get_crawl_times(target_tenant, params["namespace"])
        end

        # GET /get_result_page_per_namespace
        desc 'get_result_page_per_namespace', http_codes: {
          200 => 'Success'
        }
        params do
          requires :namespace, type: String, param_type: 'query',
            desc: 'namespace'
        end
        get 'get_result_page_per_namespace' do
          Log.debug "get_result_page_per_namespace is called: params=#{params}"
          data = ServiceUtils.get_result_page_per_namespace(target_tenant, params["namespace"])
        end

        # GET /get_vulnerability_page
        desc 'get_vulnerability_page', http_codes: {
          200 => 'Success'
        }
        params do
          requires :namespace, type: String, param_type: 'query',
            desc: 'namespace'
          requires :timestamp, type: String, param_type: 'query',
            desc: 'timestamp'
        end
        get 'get_vulnerability_page' do
          Log.debug "get_vulnerability_page is called: params=#{params}"
          data = ServiceUtils.get_vulnerability_page(target_tenant, params["namespace"], params["timestamp"])
        end


        # # GET /get_vulnerability_counts
        # desc 'get_vulnerability_counts', http_codes: {
        #   200 => 'Success'
        # }
        # get 'get_vulnerability_counts' do
        #   Log.debug "get_vulnerability_counts is called: params=#{params}"
        #   data = ServiceUtils.get_vulnerability_counts(target_tenant, params["namespace"])
        # end

        # GET /get_rule_descriptions
        desc 'get_rule_descriptions', http_codes: {
          200 => 'Success'
        }
        get 'get_rule_descriptions' do
          Log.debug "get_rule_descriptions is called"
          data = ServiceUtils.get_rule_descriptions(target_tenant)
        end

      end

    end

  end
end
