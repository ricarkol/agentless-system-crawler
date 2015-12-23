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
    class RuleGroups < Grape::API
      include SentinelDocker::Models
      PAGE_OPTS = ::SentinelDocker::API::PAGE_OPTS
      DESCRIPTIONS = ::SentinelDocker::API::DESCRIPTIONS

      prefix 'api'
      format :json
      default_format :json

      params do
        optional :api_key, type: String, param_type: 'query',
          desc: DESCRIPTIONS[:api_key]
        optional :openid, type: String, param_type: 'query',
          desc: DESCRIPTIONS[:openid]
      end
      resource :rule_groups, desc: 'Rule groups' do
        # POST /rule_groups
        desc 'Create a new rule group', entity: RuleGroup::Entity, http_codes: {
          201 => 'Rule group successfully created.',
          400 => 'Bad request. Check request body.'
        }, notes: 'Response headers: <br/><b>Location</b> header'\
                  ' indicating the URI of the newly created rule group.<br/><br/>'\
                  'To add a rule to a group, update the rule with the appropriate rule_group_id(s).'
        params do
          requires :body, type: RuleGroup::Entity, desc: 'A rule group representation', presence: false
        end
        post do
          error_out(400) unless env['api.request.body']
          error_out(400, 'A JSON object is required. Found an array.') unless env['api.request.body'].is_a? Hash
          body = Hashie::Mash.new(env['api.request.body'])
          body.delete(:id)
          begin
            rule_group = RuleGroup.new(body)
            fail rule_group.errors.full_messages.join(',') unless rule_group.save
          rescue => exception
            error_out(400, exception)
          end
          header 'Location', "#{env['REQUEST_PATH']}/#{rule_group.id}"
          rule_group
        end

        # GET /rule_groups
        desc 'List the rule groups', PAGE_OPTS.merge(
          entity: RuleGroup::Entity, is_array: true
        )
        get do
          params.update(range(headers))
          rule_groups = RuleGroup.page(offset: params[:offset], limit: params[:limit])
          set_page rule_groups
        end

        params do
          requires :id, type: String, desc: 'A rule group id'
        end
        route_param :id do
          # PUT /rule_groups/{id}
          desc 'Update a rule group', entity: RuleGroup::Entity, http_codes: {
            200 => 'Rule group successfully updated.',
            400 => 'Bad request. Check request body.',
            404 => 'Not found. The rule group does not exist.'
          }, notes: 'To add a rule to a group, update the rule with the appropriate rule_group_id(s).'
          params do
            requires :body, type: RuleGroup::Entity, desc: 'A rule group representation', presence: false
          end
          put do
            error_out(400) unless env['api.request.body'].is_a?(Hash)
            id = params[:id]
            rule_group = RuleGroup.get(id)
            error_out(404) if rule_group.nil?

            body = Hashie::Mash.new(env['api.request.body'])
            body.delete(:id)
            begin
              rule_group.update(body)
              fail rule_group.errors.full_messages.join(',') unless rule_group.save
            rescue => exception
              error_out(400, exception)
            end
            rule_group
          end

          # GET /rule_groups/{id}
          desc 'Show a rule group', entity: RuleGroup::Entity, http_codes: {
            200 => 'Success',
            404 => 'Not found. The rule group does not exist.'
          }
          get do
            RuleGroup.get(params[:id]) || error_out(404)
          end

          # DELETE /rule_groups/{id}
          desc 'Delete a rule group', http_codes: {
            204 => 'Rule group successfully deleted.',
            404 => 'Not found. The rule group does not exist.',
            500 => 'Error deleting the rule group.'
          }
          delete do
            rule_group = RuleGroup.get(params[:id])
            error_out(404) if rule_group.nil?

            if rule_group.delete
              status 204
              ''
            else
              error_out(500)
            end
          end

          # GET /rule_groups/{id}/members
          desc 'List the rule group members', PAGE_OPTS.merge(
            entity: Rule::Entity, is_array: true,
            http_codes: { 404 => 'The rule group was not found.' }
          )
          get 'members' do
            rule_group = RuleGroup.get(params[:id])
            error_out(404) if rule_group.nil?

            params.update(range(headers))
            rules = Rule.page(
              offset: params[:offset], limit: params[:limit], query: { rule_group_id: rule_group.id })

            set_page rules
          end

          # POST /rule_groups/{id}/members
          desc 'Add rules to the group', http_codes: {
            204 => 'Successfully added rules to the group.',
            404 => 'Not found. The rule group does not exist.',
            400 => 'Bad request. Check request body.'
          }
          params do
            requires :body, type: Array, presence: false,
              desc: 'An array of rule ids to add to this rule group (e.g. ["p", "q", "r", ...] )'
          end
          post 'members' do
            rule_group = RuleGroup.get(params[:id])
            error_out(404) if rule_group.nil?

            rule_ids = env['api.request.body']
            error_out(400, 'Expected an array') unless rule_ids.is_a? Array
            rule_ids.uniq!

            rules = Array(Rule.get(*rule_ids))
            error_out(400, 'No valid rules were specified') if rules.empty?

            rules.each do |rule|
              rule.add_to(rule_group)
              rule.save
            end

            status 204
            ''
          end

          # DELETE /rule_groups/{id}/members/{rule_id}
          desc 'Remove a rule from the group', http_codes: {
            204 => 'Rule successfully removed from the group.',
            404 => 'Not found. The rule group does not exist.',
            400 => 'Rule not found in the group.',
            500 => 'Error removing the rule from the group.'
          }
          params do
            requires :rule_id, type: String, desc: 'A rule id'
          end
          delete 'members/:rule_id' do
            rule_group = RuleGroup.get(params[:id])
            error_out(404) if rule_group.nil?

            rule = Rule.get(params[:rule_id])
            error_out(400) if rule.nil? || !rule.rule_group_id.include?(rule_group.id)

            rule.rule_group_id.delete(rule_group.id)
            rule.save

            status 204
            ''
          end
        end
      end
    end
  end
end
