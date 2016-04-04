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
    class ContainerGroups < Grape::API
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
      resource :container_groups, desc: 'Container groups' do
        # POST /container_groups
        desc 'Create a new container group', entity: ContainerGroup::Entity, http_codes: {
          201 => 'Container group successfully created.',
          400 => 'Bad request. Check request body.'
        }, notes: 'Response headers: <br/><b>Location</b> header'\
                  ' indicating the URI of the newly created container group.'
        params do
          requires :body, type: ContainerGroup::Entity, desc: 'A container group representation', presence: false
        end
        post do
          error_out(400) unless env['api.request.body']
          error_out(400, 'A JSON object is required. Found an array.') unless env['api.request.body'].is_a? Hash
          body = Hashie::Mash.new(env['api.request.body'])
          body.delete(:id)
          body[:period] = body[:period].to_i if body[:period]
          begin
            container_group = ContainerGroup.new(body)
            fail container_group.errors.full_messages.join(',') unless container_group.save
          rescue => exception
            error_out(400, exception)
          end
          header 'Location', "#{env['REQUEST_PATH']}/#{container_group.id}"
          container_group
        end

        # GET /container_groups
        desc 'List the container groups', PAGE_OPTS.merge(
          entity: ContainerGroup::Entity, is_array: true
        )
        get do
          params.update(range(headers))
          container_groups = ContainerGroup.page(offset: params[:offset], limit: params[:limit])
          set_page container_groups
        end

        params do
          requires :id, type: String, desc: 'A container group id'
        end
        route_param :id do
          # PUT /container_groups/{id}
          desc 'Update a container group', entity: ContainerGroup::Entity, http_codes: {
            200 => 'Container group successfully updated.',
            400 => 'Bad request. Check request body.',
            404 => 'Not found. The container group does not exist.'
          }
          params do
            requires :body, type: ContainerGroup::Entity, desc: 'A container group representation', presence: false
          end
          put do
            error_out(400) unless env['api.request.body'].is_a?(Hash)
            id = params[:id]
            container_group = ContainerGroup.get(id)
            error_out(404) if container_group.nil?

            body = Hashie::Mash.new(env['api.request.body'])
            body.delete(:id)
            body[:period] = body[:period].to_i if body[:period]
            begin
              container_group.update(body)
              fail container_group.errors.full_messages.join(',') unless container_group.save
            rescue => exception
              error_out(400, exception)
            end
            container_group
          end

          # GET /container_groups/{id}
          desc 'Show a container group', entity: ContainerGroup::Entity, http_codes: {
            200 => 'Success',
            404 => 'Not found. The container group does not exist.'
          }
          get do
            ContainerGroup.get(params[:id]) || error_out(404)
          end

          # DELETE /container_groups/{id}
          desc 'Delete a container group', http_codes: {
            204 => 'Container group successfully deleted.',
            404 => 'Not found. The container group does not exist.',
            500 => 'Error deleting the container group.'
          }
          delete do
            container_group = ContainerGroup.get(params[:id])
            error_out(404) if container_group.nil?
            if container_group.delete
              status 204
              ''
            else
              error_out(500)
            end
          end

          # POST /container_groups/{id}
          desc 'Apply rule group(s) to this container group.', http_codes: {
            204 => 'Associated all rules in the rule group, to all containers in the container group.',
            404 => 'Not found. The container group does not exist.',
            400 => 'Bad request. Check request body.'
          }
          params do
            requires :body, type: Array, presence: false,
              desc: 'An array of rule group ids to associate with this container group (e.g. ["a", "b", "c", ...] )'
          end
          post do
            container_group = ContainerGroup.get(params[:id])
            error_out(404) if container_group.nil?

            rule_group_ids = env['api.request.body']
            error_out(400, 'Expected an array') unless rule_group_ids.is_a? Array
            error_out(400, 'Array is empty') if rule_group_ids.empty?

            rule_groups = Array(RuleGroup.get(*rule_group_ids))
            rules = []
            rule_groups.each { |pg| rules += pg.rules }
            rules.uniq! { |p| p.id }

            container_group.containers.each do |container|
              rules.each do |p|
                ContainerRule.new(container_id: container.id, rule_id: p.id).save
              end
            end

            status 204
            ''
          end

          # GET /container_groups/{id}/members
          desc 'List the container group members', PAGE_OPTS.merge(
            entity: Container::Entity, is_array: true,
            http_codes: { 404 => 'The container group was not found.' }
          )
          get 'members' do
            container_group = ContainerGroup.get(params[:id])
            error_out(404) if container_group.nil?

            params.update(range(headers))
            containers = Container.page(
              offset: params[:offset], limit: params[:limit], query: { container_group_id: container_group.id })

            set_page containers
          end

          # POST /container_groups/{id}/members
          desc 'Add a container(s) to the group', http_codes: {
            204 => 'Successfully added container(s) to the group.',
            404 => 'Not found. The container group does not exist.',
            400 => 'Bad request. Check request body.'
          }
          params do
            requires :body, type: Array, presence: false,
              desc: 'An array of container ids to add to this container group (e.g. ["p", "q", "r", ...] )'
          end
          post 'members' do
            container_group = ContainerGroup.get(params[:id])
            error_out(404) if container_group.nil?

            container_ids = env['api.request.body']
            error_out(400, 'Expected an array') unless container_ids.is_a? Array
            container_ids.uniq!

            containers = Array(Container.get(*container_ids))
            error_out(400, 'No valid containers were specified.') if containers.empty?

            containers.each do |container|
              container.add_to(container_group)
              container.save
            end

            status 204
            ''
          end

          # DELETE /container_groups/{id}/members/{container_id}
          desc 'Remove a container from the group', http_codes: {
            204 => 'Container successfully removed from the group.',
            404 => 'Not found. The container group does not exist.',
            400 => 'Container not found in the group.',
            500 => 'Error removing the container from the group.'
          }
          params do
            requires :container_id, type: String, desc: 'A container id'
          end
          delete 'members/:container_id' do
            container_group = ContainerGroup.get(params[:id])
            error_out(404) if container_group.nil?

            container = Container.get(params[:container_id])
            error_out(400) if container.nil? || !container.container_group_id.include?(container_group.id)

            container.container_group_id.delete(container_group.id)
            container.save

            status 204
            ''
          end

          # GET /container_groups/{id}/compliance - Calculate a container group's compliance
          desc 'Show compliance level of a container group', http_codes: {
            200 => 'Success',
            404 => 'Not found. The container group does not exist.'
          }, notes: 'Returns <em>true</em> if the containers in the group are compliant, and <em>false</em> otherwise.'\
                    '<br/>Compliance is calculated based on whether there all rules associated'\
                    ' with all the containers in the group pass.'
          get 'compliance' do
            container_group = ContainerGroup.get(params[:id]) or error_out(404)

            container_group.compliant?
          end
        end
      end
    end
  end
end
