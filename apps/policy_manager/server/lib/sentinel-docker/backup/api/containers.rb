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
    class Containers < Grape::API
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
      resource :containers, desc: 'Container registration and management' do

        # POST /containers - Create container. Register a new node in Chef, and bootstrap the container.
        desc 'Register a new container', http_codes: {
          201 => 'Container successfully created.',
          400 => 'Bad request. Check request body.',
          403 => 'Registering these containers will exceed the preconfigured maximum supported.'
        }, notes: 'Response headers: <br/><b>Location</b> header'\
                  ' indicating the URI of the newly registered container.<br/><br/>'\
                  'You can also post an array of containers for bulk registration.'

        params do
          requires :body, type: Container::Entity, desc: 'A container representation', presence: false
        end
        post do
          error_out(400, "body=#{env['api.request.body']}") unless env['api.request.body'].is_a?(Hash) || env['api.request.body'].is_a?(Array)

          body = env['api.request.body']
          # Check max containers limit
          size = body.is_a?(Array) ? body.size : 1
          total_containers = Container.page(limit: 1).total
          if (total_containers + size) > SentinelDocker::Config.limits.max_containers
            error_out(403, "#{SentinelDocker::Config.limits.max_containers} containers supported."\
                           " There is a total of #{total_containers} containers registered."\
                           " #{size} incoming container(s) found in this request.")
          end

          if body.is_a? Hash
            container = DockerUtil.container(body)
            header 'Location', "#{env['REQUEST_PATH']}/#{container.id}"
            present container
          else
            res = []
            body.each do |conf|
              begin
                container = DockerUtil.container(conf)
                res << container
              rescue => e
              end
            end
            res
          end

        end

        # GET /containers - List out the containers. Support paging.
        desc 'List the containers', PAGE_OPTS.merge(
          entity: Container::Entity,
          is_array: true
        )
        get do
          containers = Container.page(range(headers))
          set_page containers
          present containers
        end

        params do
          requires :id, type: String, desc: 'A container\'s id'
        end
        route_param :id do

          # PUT /container/{id} - Update a container.
          desc 'Update a container', http_codes: {
            200 => 'Container successfully updated.',
            400 => 'Bad request. Check request body.',
            404 => 'Not found. Container does not exist'
          }
          params do
            requires :body, type: Container::Entity, desc: 'A container representation', presence: false
          end
          put do
            error_out(400) unless env['api.request.body'].is_a?(Hash)
            id = params[:id]
            container = Container.get(id)
            error_out(404) if container.nil?
            body = Hashie::Mash.new(env['api.request.body'].merge(id: id))
            body.delete(:container_group_id)
            begin
              container.update(body)
              fail container.errors.full_messages.join(',') unless container.save
            rescue => exception
              error_out(400, exception)
            end
            present container
          end

          # GET /container/{id} - Show a container
          desc 'Show a container', entity: Container::Entity, http_codes: {
            200 => 'Success',
            404 => 'Not found. The container does not exist.'
          }
          get do
            container = Container.get(params[:id])
            error_out(404) if container.nil?
            present container
          end

          # DELETE /container/{id} - Delete a container. Remove node from chef
          desc 'Deregister a container', http_codes: {
            204 => 'Container successfully deleted.',
            404 => 'Not found. Container does not exist',
            500 => 'Error deleting the container.'
          }
          delete do
            container = Container.get(params[:id])
            error_out(404) if container.nil?

            if container.delete
              status 204
              ''
            else
              error_out(500)
            end
          end

          # GET /container/{id}/run - Run the rule in check or fix mode.
          desc 'Run all container rules in their default mode', entity: ContainerRule::Entity,
          is_array: true, http_codes: {
            200 => 'Successful run.',
            204 => 'The container has no associated rules to run.',
            404 => 'Not found. The container does not exist.'
          }
          params do
            optional :use_period, type: Boolean,
              desc: 'Take the container group period interval into account?',
              default: 'false'
          end
          get 'run' do
            container = Container.get(params[:id])
            error_out(404, 'The container was not found.') if container.nil?

            container_rules = container.container_rules
            if container_rules.empty?
              status 204
              break ''
            end

            # Find current user
            user = current_user
            user = user.as_json if user

            break DockerUtil.run_rules(container_rules, user) unless params[:use_period]

            # Find smallest period from all the container groups
            groups = container.container_groups
            memo = groups.size > 0 ? groups.first.period : 0
            period = container.container_groups.inject(memo) do |a, g|
              a = a.period if a.respond_to? :period
              g.period < a ? g.period : a
            end

            # Find the container rules that have not been run within the last period (hours)
            period = Time.now.to_i - (period.to_i * 3600) # convert to seconds ago
            due_rules = container_rules.select do |sp|
              sp.last_timestamp.nil? || sp.last_timestamp < period
            end

            DockerUtil.run_rules(due_rules, user) || ''
          end

          # Add container rules api here
          instance_eval(&SentinelDocker::API::ContainerRules)

          # GET /containers/{id}/compliance - Calculate a container's compliance
          desc 'Show compliance level of a container', http_codes: {
            200 => 'Success',
            404 => 'Not found. The container does not exist.'
          }, notes: 'Returns <em>true</em> if the container is compliant, and <em>false</em> otherwise.'\
                    '<br/>Compliance is calculated based on whether there all rules associated'\
                    ' with the container pass.'
          get 'compliance' do
            container = Container.get(params[:id]) or error_out(404)
            container.compliant?
          end

          # # GET /containers/{id}/installer - Get install package
          # desc 'Get install package for a container', http_codes: {
          #   200 => 'Success',
          #   404 => 'Not found. The container does not exist.',
          #   500 => 'Error creating install package'
          # }, notes: 'Returns <em>install package file</em> if the container has been registered on sentinel server.'
          # get 'installer' do
          #   container = Container.get(params[:id]) or error_out(404)

          #   temp_dir = Dir.mktmpdir
          #   begin
          #     package_file_path = Bootstrap.installer(container, temp_dir)
          #     content_type 'application/octet-stream'
          #     header['Content-Disposition'] = "attachment; filename=\"installer_#{container.node_name}.bsx\""
          #     env['api.format'] = :binary
          #     File.open(package_file_path).read
          #   rescue => exception
          #     error_out(500, exception)
          #   ensure
          #     FileUtils.remove_entry_secure temp_dir
          #   end
          # end
        end
      end
    end
  end
end
