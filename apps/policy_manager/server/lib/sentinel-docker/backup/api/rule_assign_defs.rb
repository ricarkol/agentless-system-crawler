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
    class RuleAssignDefs < Grape::API
      include SentinelDocker::Models
      PAGE_OPTS = ::SentinelDocker::API::PAGE_OPTS
      DESCRIPTIONS = ::SentinelDocker::API::DESCRIPTIONS

      prefix 'api'
      format :json
      default_format :json

      # helpers SentinelDocker::DockerUtil

      params do
        optional :api_key, type: String, param_type: 'query',
          desc: DESCRIPTIONS[:api_key]
        optional :openid, type: String, param_type: 'query',
          desc: DESCRIPTIONS[:openid]
      end
      resource :rule_assign_defs, desc: 'Rule assignment management' do

        #POST /rule_assign_defs - Create rule_assign_def
        desc 'Add new rule_assign_def', {
          entity: RuleAssignDef::Entity,
          nickname: "addNewRule",
          http_codes: {
            201 => 'Success',
            400 => 'Bad request.'
          }, notes: 'Response headers: <br/><b>Location</b> header'\
                    ' indicating the URI of the newly created rule_assign_def.'
        }
        params do
          requires :body, type: RuleAssignDef::Entity, desc: 'A rule representation', presence: false
        end
        post do
          error_out(400) unless env['api.request.body'].is_a?(Hash)
          body = Hashie::Mash.new(env['api.request.body'])
          body.reject! { |k| %w( id ).include? k }
          rule_assign_def = nil
          begin
            rule_assign_def = RuleAssignDef.new(body)
            fail rule_assign_def.errors.full_messages.join(',') unless rule_assign_def.save
          rescue => exception
            error_out(400, exception)
          end
          header 'Location', "#{env['REQUEST_PATH']}/#{rule_assign_def.id}"
          rule_assign_def
        end



        # GET /rule_assign_defs - List out the rule_assign_defs. Support paging.
        desc 'List the rule_assign_defs', PAGE_OPTS.merge(
          entity: RuleAssignDef::Entity,
          is_array: true
        )
        get do
          params.update(range(headers))
          rule_assign_defs = RuleAssignDef.page(offset: params[:offset], limit: params[:limit])
          set_page rule_assign_defs
        end

        params do
          requires :id, type: String, desc: 'A rule_assign_def id'
        end
        route_param :id do
          # PUT /rule_assign_defs/{id} - Update a rule_assign_def.
          desc 'Update a rule_assign_def', entity: RuleAssignDef::Entity, http_codes: {
            200 => 'RuleAssignDef successfully updated.',
            400 => 'Bad request. Check request body.',
            404 => 'Not found. The rule_assign_def does not exist.'
          }, notes: 'Only the rule_assign_def parameters, and grace period can be updated.'
          params do
            requires :body, type: RuleAssignDef::Entity, desc: 'A rule_assign_def representation', presence: false
          end
          put do
            error_out(400) unless env['api.request.body'].is_a?(Hash)
            id = params[:id]
            rule_assign_def = RuleAssignDef.get(id)
            error_out(404) if rule_assign_def.nil?
            rule_assign_def.parameters ||= {}

            body = Hashie::Mash.new(env['api.request.body'].merge(id: id))

            begin
              rule_assign_def.parameters = rule_assign_def.parameters.merge(body[:parameters]) if body.key?(:parameters)
              rule_assign_def.grace_period = body[:grace_period] if body.key?(:grace_period)
              fail rule_assign_def.errors.full_messages.join(',') unless rule_assign_def.save
            rescue => exception
              error_out(400, exception)
            end
            rule_assign_def
          end

          # GET /rule_assign_defs/{id} - Show a rule_assign_def
          desc 'Show a rule_assign_def', entity: RuleAssignDef::Entity, http_codes: {
            200 => 'Success',
            404 => 'Not found. The rule_assign_def does not exist.'
          }
          get do
            RuleAssignDef.get(params[:id]) || error_out(404)
          end

          # GET /rule_assign_defs/{id}/parameters - Show a rule_assign_def parameters only
          desc 'Show a rule_assign_def\'s parameters only', http_codes: {
            200 => 'Success',
            404 => 'Not found. The rule_assign_def does not exist.'
          }
          get :parameters do
            rule_assign_def = RuleAssignDef.get(params[:id])
            error_out(404) if rule_assign_def.nil?
            { rule_assign_def.name => rule_assign_def.parameters }
          end

          # DELETE /rule_assign_defs/{id} - Delete a rule_assign_def. Remove node from chef
          # desc 'Delete a rule_assign_def', http_codes: {
          #   200 => 'RuleAssignDef successfully deleted.',
          #   404 => 'Not found. The rule_assign_def does not exist.',
          #   500 => 'Error deleting the rule_assign_def.'
          # }
          # delete do
          #   rule_assign_def = RuleAssignDef.get(params[:id])
          #   error_out(404) if rule_assign_def.nil?
          #   rule_assign_def.delete
          # end
        end
      end
    end
  end
end
