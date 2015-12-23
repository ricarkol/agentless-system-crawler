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
    class Groups < Grape::API
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
        optional :tenant, type: String, param_type: 'query', 
          desc: DESCRIPTIONS[:tenant]
      end
      resource :groups, desc: 'Groups' do

        # GET 
        desc 'List the groups', PAGE_OPTS.merge(
          entity: Group::Entity, is_array: true,
          http_codes: {
            200 => 'Success',
            401 => 'Authentication required.',
            403 => 'Forbidden - unauthorized request'
          }
        )
        get do
          error_out(401, "authentication required") unless current_user
          tenant = target_tenant
          error_out(403) if tenant.nil?
          params.update(range(headers))
          groups = Group.page(offset: params[:offset], limit: params[:limit], query: { tenant_id: tenant.id })
          set_page groups
        end

        # POST /groups
        desc 'Create a new group', entity: Group::Entity, http_codes: {
          201 => 'group successfully created.',
          400 => 'Bad request. Check request body.',
          401 => 'Authentication required.',
          403 => 'Forbidden - unauthorized request'
        }, notes: 'Response headers: <br/><b>Location</b> header'\
          ' indicating the URI of the newly created tenant.'
        params do
          requires :body, type: Group::Entity, desc: 'A group representation', presence: false
        end
        post do
          error_out(401, "authentication required") unless current_user
          tenant = target_tenant
          error_out(403) if tenant.nil?
          error_out(400) unless env['api.request.body']
          error_out(400, 'A JSON object is required. Found an array.') unless env['api.request.body'].is_a? Hash
          body = Hashie::Mash.new(env['api.request.body'])
          error_out(400, 'no name specified') unless body[:name] && !body[:name].empty?
          error_out(400, 'same group name already exists.') unless tenant.groups.select{|g| g.name == body[:name]}.empty?
          begin
            group = Group.new(body.slice(:name, :default, :auto_assign, :rule_id))
            group.tenant_id = tenant.id
            fail group.errors.full_messages.join(',') unless group.save
          rescue => exception
            error_out(400, exception)
          end
          header 'Location', "#{env['REQUEST_PATH']}/#{group.id}"
          group
        end

        params do
          requires :id, type: String, desc: 'A group id'
        end
        route_param :id do

          # GET /groups/{id}
          desc 'Show a group', entity: Group::Entity, http_codes: {
            200 => 'Success',
            401 => 'Authentication required.',
            403 => 'Forbidden - unauthorized request',            
            404 => 'Not found. The group does not exist.'
          }
          get do
            error_out(401, "authentication required") unless current_user
            tenant = target_tenant
            error_out(403) if tenant.nil?
            tenant.groups.select {|g| g.id == params[:id]}.first ||  error_out(404)
          end


          # PUT /groups/{id}
          desc 'Update a group', entity: Group::Entity, http_codes: {
            200 => 'group successfully updated.',
            400 => 'Bad request. Check request body.',
            401 => 'Authentication required.',            
            403 => 'Forbidden - unauthorized request',            
            404 => 'Not found. The group does not exist.'
          }
          params do
            requires :body, type: Group::Entity, desc: 'A group representation', presence: false
          end
          put do
            error_out(400) unless env['api.request.body'].is_a?(Hash)
            error_out(401, "authentication required") unless current_user
            tenant = target_tenant
            error_out(403) if tenant.nil?
            group = tenant.groups.select {|g| g.id == params[:id]}.first
            error_out(404) if group.nil?

            body = Hashie::Mash.new(env['api.request.body'])
            begin
              group.update(body.slice(:name, :default, :auto_assign, :rule_id))
              fail group.errors.full_messages.join(',') unless group.save
            rescue => exception
              error_out(400, exception)
            end
            group
          end

          # DELETE /tenants/{id}/groups/{group_id}
          desc 'Remove a group from the tenant', http_codes: {
            204 => 'Rule successfully removed from the tenant.',
            400 => 'group not found in the tenant.',
            401 => 'Authentication required.',            
            403 => 'Forbidden - unauthorized request',            
            404 => 'Not found. The tenant does not exist.',
            500 => 'Error removing the group from the tenant.'
          }
          delete do
            error_out(401, "authentication required") unless current_user
            tenant = target_tenant
            error_out(403) if tenant.nil?
            group = tenant.groups.select{|g| g.id == params[:id]}.first
            error_out(404) unless group
            error_out(500) if group.default
            group.delete
            status 204
            ''
          end
        end
      end
    end
  end
end
