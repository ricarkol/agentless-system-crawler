# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
require 'securerandom'
require 'json'

module SentinelDocker
  module API
    ContainerRules = proc do
      Container = SentinelDocker::Models::Container
      ContainerRule = SentinelDocker::Models::ContainerRule
      ContainerRuleRun = SentinelDocker::Models::ContainerRuleRun

      resource :rules do

        # POST /container_rules - Create container rule.
        desc 'Create a new container rule', entity: ContainerRule::Entity, http_codes: {
          201 => 'Container rule successfully created.',
          400 => 'Bad request. Check request body.',
          404 => 'Not found. Container does not exist.'
        }, notes: 'Response headers: <br/><b>Location</b> header'\
                  ' indicating the URI of the newly registered container rule.'
        params do
          requires :body, type: ContainerRule::Entity, desc: 'A container rule representation',
            presence: false
        end
        post do
          error_out(401) unless env['api.request.body'].is_a?(Hash)
          container_id = params[:id]
          error_out(404) if Container.get(container_id).nil?
          body = Hashie::Mash.new(env['api.request.body'])
          body.reject! { |k| %w(id last_status last_output last_user last_timestamp).include? k }
          body[:container_id] = container_id
          begin
            container_rule = ContainerRule.new(body)
            fail 'Bad rule_assign_def_id' unless container_rule.rule_assign_def
            fail container_rule.errors.full_messages.join(',') unless container_rule.save
          rescue => exception
            error_out(400, exception)
          end
          header 'Location', "#{env['REQUEST_PATH']}/#{container_rule.id}"
          container_rule
        end

        # GET /container_rules - List out the container rules. Support paging.
        desc 'List the container rules', PAGE_OPTS.merge(
          entity: ContainerRule::Entity,
          is_array: true,
          http_codes: { 404 => 'Not found. Container does not exist.' }
        )
        get do
          error_out(404) if Container.get(params[:id]).nil?
          params.update(range(headers))
          container_rules = ContainerRule.page(
            offset: params[:offset], limit: params[:limit], query: { container_id: params[:id] })
          set_page container_rules
        end

        params do
          requires :container_rule_id, type: String, desc: 'A container rule id'
        end
        route_param :container_rule_id do
          # PUT /container_rules/{id} - Update a container rule.
          desc 'Update a container rule', entity: ContainerRule::Entity, http_codes: {
            200 => 'Container rule successfully updated.',
            400 => 'Bad request. Check request body.',
            404 => 'Not found. The container rule does not exist.'
          }, notes: 'You can only update <em>auto_remedy</em>, <em>ignore_failure</em>,'\
                    ' and <em>ignore_justification</em>.'
          params do
            requires :body, type: ContainerRule::Entity, desc: 'A container rule representation',
              presence: false
          end
          put do
            error_out(400) unless env['api.request.body'].is_a?(Hash)
            error_out(404, 'The container was not found.') if Container.get(params[:id]).nil?
            id = params[:container_rule_id]
            container_rule = ContainerRule.get(id)
            error_out(404, container_rule.as_json) if container_rule.nil? || container_rule.container_id != params[:id]

            body = Hashie::Mash.new(env['api.request.body'])
            body.reject! { |k| %w(id container_id "rule_assign_def_id last_timestamp last_output last_status last_user).include? k }
#            error_out(400, body)

            begin
              container_rule.update(body)
              fail container_rule.errors.full_messages.join(',') unless container_rule.save
            rescue => exception
              error_out(400, exception)
            end
            container_rule
          end

          # GET /container_rules/{id} - Show a container rule
          desc 'Show a container rule', entity: ContainerRule::Entity, http_codes: {
            200 => 'Success',
            404 => 'Not found. The container rule does not exist.'
          }
          get do
            container = Container.get(params[:id])
            error_out(404, 'The container was not found.') if container.nil?
            container_rule = ContainerRule.get(params[:container_rule_id])
            error_out(404) if container_rule.nil? || container_rule.container_id != container.id
            container_rule
          end

          # DELETE /container_rules/{id} - Delete a container rule. Remove node from chef
          desc 'Delete a container rule', http_codes: {
            204 => 'Container rule successfully deleted.',
            404 => 'Not found. The container rule does not exist.',
            500 => 'Error deleting the container rule.'
          }
          delete do
            container = Container.get(params[:id])
            error_out(404, 'The container was not found.') if container.nil?

            container_rule = ContainerRule.get(params[:container_rule_id])
            error_out(404) if container_rule.nil? || container_rule.container_id != container.id

            if container_rule.delete
              status 204
              ''
            else
              error_out(500)
            end
          end

          # GET /container_rules/{id}/run - Run the rule in check or fix mode.
          desc 'Run a container rule in check or fix mode', entity: ContainerRule::Entity, http_codes: {
            200 => 'Successful run.',
            404 => 'Not found. The container rule does not exist.',
            400 => 'Bad request. Check that the mode parameter is either "fix" or "check".',
            500 => 'An internal error was encountered'
          }
          params do
            optional :mode, type: String, desc: 'Run this in fix or check mode',
              values: %w(check fix)
          end
          get 'run' do
            container = Container.get(params[:id])
            error_out(404, 'The container was not found.') if container.nil?

            id = params[:container_rule_id]

            container_rule = ContainerRule.get(id)
            error_out(404) if container_rule.nil? || container_rule.container_id != container.id

            rule = container_rule.rule
            error_out(404, 'Related rule does not exist.') if rule.nil?

            # Find current user
            user = current_user
            user = user.as_json if user

            DockerUtil.run_rule(container_rule, user)
          end

          # GET /container_rules/{id}/runs - List out the container rule runs. Support paging.
          desc 'List the previous container rule runs', PAGE_OPTS.merge(
            entity: ContainerRuleRun::Entity,
            is_array: true,
            http_codes: { 404 => 'Not found' }
          )
          params do
            optional :mode, type: String, desc: 'Filter on run mode (check or fix)',
              values: %w(check fix)
          end
          get 'runs' do
            container = Container.get(params[:id])
            error_out(404, 'The container was not found.') if container.nil?

            params.update(range(headers))
            id = params[:container_rule_id]
            mode = params[:mode]

            container_rule = ContainerRule.get(id)
            error_out(404, 'The rule was not found.') \
              if container_rule.nil? || container_rule.container_id != container.id

            query = { container_rule_id: id }
            query.update(mode: mode) if mode

            rule_runs = ContainerRuleRun.page(
              offset: params[:offset],
              limit: params[:limit],
              sort: '_timestamp:desc',
              query: query
            )
            #rule_runs.sort!{ |a,b| a.timestamp > b.timestamp ? -1 : 1}
            set_page rule_runs
          end
        end
      end
    end
  end
end
