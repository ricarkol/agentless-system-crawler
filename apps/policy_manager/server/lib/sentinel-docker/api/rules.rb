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
    class Rules < Grape::API
      include SentinelDocker::Models
      PAGE_OPTS = ::SentinelDocker::API::PAGE_OPTS
      DESCRIPTIONS = ::SentinelDocker::API::DESCRIPTIONS

      RULE_DIR = '/home/sentinel/rulezips'

      prefix 'api'
      format :json
      default_format :json

      # helpers SentinelDocker::DockerUtil

      params do
        optional :api_key, type: String, param_type: 'query',
          desc: DESCRIPTIONS[:api_key]
        optional :openid, type: String, param_type: 'query',
          desc: DESCRIPTIONS[:openid]
        optional :tenant, type: String, param_type: 'query', 
          desc: DESCRIPTIONS[:tenant]        
      end
      resource :rules, desc: 'Rule management' do

        #POST /rules - Create rule
        desc 'Add new rule', {
          entity: Rule::Entity,
          nickname: "addNewRule",
          http_codes: {
            201 => 'Success',
            400 => 'Bad request.'
          }, notes: 'Response headers: <br/><b>Location</b> header'\
          ' indicating the URI of the newly created rule.'
        }
        params do
          requires :rule_zip, type: Rack::Multipart::UploadedFile, desc: "zip file containing a rule script."
        end
        post do
          t = target_tenant
          fail 'no tenant specified' unless t
          rule_zip = params[:rule_zip]
          raise "#no rule zip file" if rule_zip.nil?

          zipfile = rule_zip.tempfile.path
          begin
            metadata = Util.load_metadata(zipfile)
            fail "fail to load metadata" unless metadata
            fail "no name specified in metadata" unless metadata['name']

            rule = Util.set_rule(t, metadata, zipfile)
            header 'Location', "#{env['REQUEST_PATH']}/#{rule.id}"
            rule
          rescue => exception
            SentinelDocker::Log.error exception.backtrace.join("\n")
            error_out(400, exception)
          end
        end


        # POST /rules - Create rule
        # desc 'Add new rule', {
        #   entity: Rule::Entity,
        #   nickname: "addNewRule",
        #   http_codes: {
        #     201 => 'Success',
        #     400 => 'Bad request. Check rule zip file.',
        #     409 => 'The specified rule already exists.'
        #   }, notes: 'Response headers: <br/><b>Location</b> header'\
        #             ' indicating the URI of the newly created rule.'
        # }
        # params do
        #   requires :rule_zip, type: Rack::Multipart::UploadedFile, desc: "zip file containing a rule cookbook (cookbook name must be exactly same as rule name, which should be started with \"rule_\"). Request would not be accepted if same rule name has been already registered in chef server."
        # end
        # post do

        #   #1. load parameter
        #   rule_zip = params[:rule_zip]
        #   raise "#no rule zip file" if rule_zip.nil?

        #   temp_zip = rule_zip.tempfile

        #   #2. unzip file in temp_dir

        #   sentinel_user = `whoami`.chomp
        #   sentinel_user_home = ENV['HOME']
        #   sentinel_group = `groups`.split(' ').first

        #   cookbook_dir = File.join(sentinel_user_home, "chef-repo/cookbooks")

        #   temp_dir = Dir.mktmpdir
        #   rule_name = nil
        #   begin

        #     #extract zip file
        #     rule_name = extract_files(temp_zip.path, temp_dir)

        #     #check if rule_name has not been registered yet
        #     rule = SentinelDocker::Models::Rule.find(query: { name: rule_name })
        #     error_out(409, "#{rule_name} already exists.") unless rule.empty?

        #     rule_dir = File.join(cookbook_dir, rule_name)

        #     #delete old files
        #     FileUtils.rm_r(rule_dir) if Dir.exists? rule_dir

        #     #copy temp_dir to chef_repo
        #     FileUtils.cp_r(temp_dir, rule_dir)
        #     FileUtils.chmod_R(0755, rule_dir)
        #     FileUtils.chown_R(sentinel_user, sentinel_group, rule_dir)

        #   rescue => exception
        #     error_out(400, exception)
        #   ensure
        #     FileUtils.rm_r(temp_dir)
        #   end

        #   #4. do "knife cookbook upload"
        #   begin
        #     SentinelDocker::DockerUtil.with_clean_env do
        #       cmd = `knife cookbook upload #{rule_name} --cookbook-path #{cookbook_dir} -y`
        #       raise "fail to upload cookbook #{rule_name} to chef server" unless $?.success?
        #     end
        #   rescue => exception
        #     error_out(400, exception)
        #   end

        #   #5. get metadata and sync rule
        #   rule = SentinelDocker::Models::Rule.find(query: { name: rule_name }).first
        #   SentinelDocker::DockerUtil.with_clean_env do
        #     rule_version = `knife cookbook show #{rule_name} | awk '{ print $2 }'`.chomp
        #     if $?.success?
        #       metadata = load_metadata(rule_name, rule_version)
        #       if rule.nil?
        #         rule = SentinelDocker::Models::Rule.new(metadata)
        #         error_out(400, user.errors.full_messages.join(',')) unless rule.save
        #       else
        #         rule.update!(metadata)
        #       end
        #     else
        #       error_out(400, 'Could not get rule version.')
        #     end
        #   end

        #   header 'Location', "#{env['REQUEST_PATH']}/#{rule.id}"
        #   rule
        # end


        # GET /rules - List out the rules. Support paging.
        desc 'List the rules', PAGE_OPTS.merge(
          entity: Rule::Entity,
          is_array: true
        )
        get do
          error_out(401, "authentication required") unless current_user
          t = target_tenant
          error_out(403) unless t
          params.update(range(headers))
          rules = Rule.page(offset: params[:offset], limit: params[:limit], query:{ 'tenant_id' => t.id })
          set_page rules
        end

        # DELETE /rules/bulk_delete - Delete rules
        desc 'Delete rules', http_codes: {
          204 => 'Rule successfully deleted.',
          400 => 'Bad request.',
          404 => 'Not found. The rule does not exist.',
          500 => 'Error deleting the rule.'
        }
        params do
          requires :body, type: Array, desc: 'a list of rules to be deleted', presence: false
        end
        delete 'bulk_delete' do
          error_out(401, "authentication required") unless current_user
          t = target_tenant
          error_out(403) unless t
          error_out(400, "no array specified in body") unless env['api.request.body'].is_a?(Array)
          body = env['api.request.body']
          rules = []
          body.each do |id|
            rule = t.rules.select{|r| r.id == id}.first
            error_out(404) if rule.nil?
            rules << rule
          end

          rules.each do |r|
            r.delete
          end
          status 204
          ''
        end


        params do
          requires :id, type: String, desc: 'A rule id'
        end
        route_param :id do
          # PUT /rules/{id} - Update a rule.
          desc 'Update a rule', entity: Rule::Entity, http_codes: {
            200 => 'Rule successfully updated.',
            400 => 'Bad request. Check request body.',
            401 => 'Authentication required.',
            403 => 'Forbidden - unauthorized request',
            404 => 'Not found. The rule does not exist.'
          }, notes: 'Only the rule parameters, and grace period can be updated.'
          params do
            requires :body, type: Rule::Entity, desc: 'A rule representation', presence: false
          end
          put do
            error_out(401, "authentication required") unless current_user
            t = target_tenant
            error_out(403) unless t
            error_out(400) unless env['api.request.body'].is_a?(Hash)
            id = params[:id]
            rule = t.rules.select{ |r| r.id == id }.first
            error_out(404) if rule.nil?
            rule.parameters ||= {}

            body = Hashie::Mash.new(env['api.request.body'].merge(id: id))

            begin
              rule.description = body[:description] if body.key?(:description)
              rule.description = body[:long_description] if body.key?(:long_description)
              rule.parameters = rule.parameters.merge(body[:parameters]) if body.key?(:parameters)
              rule.grace_period = body[:grace_period] if body.key?(:grace_period)
              fail rule.errors.full_messages.join(',') unless rule.save
            rescue => exception
              error_out(400, exception)
            end
            rule
          end

          # GET /rules/{id} - Show a rule
          desc 'Show a rule', entity: Rule::Entity, http_codes: {
            200 => 'Success',
            404 => 'Not found. The rule does not exist.'
          }
          get do
            t = target_tenant
            fail 'no tenant specified' unless t
            fail 'no id specified' unless params[:id]
            t.rules.select {|r| r.id == params[:id]}.first || error_out(404)
          end

          # GET /rules/{id}/files - Download rule zip file
          desc 'Get rule zip file', entity: Rule::Entity, http_codes: {
            200 => 'Success',
            401 => 'Authentication required.',
            403 => 'Forbidden - unauthorized request',
            404 => 'Not found. The rule zip does not exist.',
            500 => 'Error getting rule zip file'
          }
          get 'files' do
            t = target_tenant
            error_out(401, "authentication required") unless current_user
            t = target_tenant
            error_out(403) unless t
            error_out(400, 'no id specified') unless params[:id]
            rule = t.rules.select {|r| r.id == params[:id]}.first
            error_out(404) unless rule
            begin
              zip_file_path = Util.rule_zip_path(t, rule)
              content_type 'application/octet-stream' 
              header['Content-Disposition'] = "attachment; filename=\"#{rule.name}.zip\""
              env['api.format'] = :binary
              File.open(zip_file_path).read
            rescue => exception
              error_out(500, exception)
            end
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




          # # GET /rules/{id}/parameters - Show a rule parameters only
          # desc 'Show a rule\'s parameters only', http_codes: {
          #   200 => 'Success',
          #   404 => 'Not found. The rule does not exist.'
          # }
          # get :parameters do
          #   t = target_tenant
          #   fail 'no tenant specified' unless t
          #   rule = t.rules.select {|r| r.id == params[:id]}
          #   error_out(404) if rule.nil?
          #   { rule.name => rule.parameters }
          # end

          # DELETE /rules/{id} - Delete a rule. Remove node from chef
          desc 'Delete a rule', http_codes: {
            204 => 'Rule successfully deleted.',
            401 => 'Authentication required.',
            403 => 'Forbidden - unauthorized request',
            404 => 'Not found. The rule does not exist.',
            500 => 'Error deleting the rule.'
          }
          delete do
            error_out(401, "authentication required") unless current_user
            fail 'no id specified' unless params[:id]
            tenant = target_tenant
            error_out(403, 'unauthorized operation') unless tenant

            rule = tenant.rules.select { |r| r.id == params[:id]}.first
            error_out(404) if rule.nil?
            if rule.delete
              status 204
              ''
            else
              error_out(500)
            end
          end
        end
      end
    end
  end
end
