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
    class Users < Grape::API
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
      resource :users, desc: 'User management' do

        # POST /users - Create a user.
        desc 'Create a new user', entity: User::Entity, http_codes: {
          201 => 'User successfully created.',
          400 => 'Bad request. Check request body.',
          403 => 'Forbidden - unauthorized request'
        }, notes: 'Response headers: <br/><b>Location</b> header'\
                  ' indicating the URI of the new user.<br/><br/>'\
                  'You can also post an array of users for bulk creation.'
        params do
          requires :body, type: User::Entity, desc: 'A user representation', presence: false
        end
        post do
          error_out(403, 'unauthorized operation') unless current_user.tenant.name == 'IBM'          
          error_out(400) unless env['api.request.body'].is_a?(Hash) || env['api.request.body'].is_a?(Array)
          body = Hashie::Mash.new(env['api.request.body'])
          users = []
          body = [body] if body.is_a? Hash
          body.each do |part|
            identity = part[:identity]
            tenant_id = part[:tenant_id]
            begin
              fail "Identity url needs to be supplied for #{part}" if identity.nil?
              fail "tenant id needs to be supplied for #{part}" if tenant_id.nil?
              t = Tenant.get(tenant_id)
              fail "tenant does not exist for #{tenant_id}" unless t
              fail "user already exists" unless User.find(query: {identity: identity}).empty?
              user = User.new(part.slice(:identity, :fullname, :email, :api_key, :tenant_id))
              fail user.errors.full_messages.join(',') unless user.save
            rescue => exception
              error_out(400, exception)
            end
            users << user
          end

          if users.size == 1
            header 'Location', "#{env['REQUEST_PATH']}/#{users[0].id}"
            present users[0], user: current_user
          else
            present users, user: current_user
          end
        end

        # GET /users - List out the users. Support paging.
        desc 'List the users', PAGE_OPTS.merge(
          entity: User::Entity,
          is_array: true
        )
        get do
          error_out(401, "authentication required") unless current_user
          t = target_tenant
          error_out(403) unless t
          # users = User.page(range(headers))
          params.update(range(headers))
          users = User.page(offset: params[:offset], limit: params[:limit], query:{ 'tenant_id' => t.id })
          present set_page(users), user: current_user
        end

        params do
          requires :id, type: String, desc: 'A user\'s id'
        end
        route_param :id do
          # PUT /users/{id} - Update a user.
          desc 'Update a user', entity: User::Entity, http_codes: {
            200 => 'User successfully updated.',
            400 => 'Bad request. Check request body.',
            401 => 'Authentication required.',
            403 => 'Forbidden - unauthorized request',            
            404 => 'Not found. User does not exist'
          }
          params do
            requires :body, type: User::Entity, desc: 'A user representation', presence: false
          end
          put do
            error_out(401, "authentication required") unless current_user
            t = target_tenant
            error_out(403) unless t
            error_out(400) unless env['api.request.body'].is_a?(Hash)
            id = params[:id]
            error_out(400) unless id
            user = t.select{|u| u.id == id}.first
            error_out(404) if user.nil?

            body = Hashie::Mash.new(env['api.request.body'])
            body.delete(:id)
            body
            begin
              user.update(body.slice(:fullname, :email))
              fail user.errors.full_messages.join(',') unless user.save
            rescue => exception
              error_out(400, exception)
            end
            present user, user: current_user
          end

          # GET /users/{id} - Show a user
          desc 'Show a user', entity: User::Entity, http_codes: {
            200 => 'Success',
            404 => 'Not found. The user does not exist.'
          }
          get do
            t = target_tenant
            fail 'no tenant specified' unless t
            fail 'no id specified' unless params[:id]
            user_id = params[:id]
            user = user_id == 'me' ? current_user : t.users.select{|u| u.id==user_id}.first
            user ? present(user, user: current_user) : error_out(404)
          end

          # DELETE /users/{id} - Delete a user.
          desc 'Delete a user', http_codes: {
            204 => 'User successfully deleted.',
            401 => 'Authentication required.',
            403 => 'Forbidden - unauthorized request',
            404 => 'Not found. User does not exist',
            500 => 'Error deleting the user.'
          }
          delete do
            error_out(401, "authentication required") unless current_user
            fail 'no id specified' unless params[:id]
            tenant = target_tenant
            error_out(403, 'unauthorized operation') unless tenant            
            user = t.users.select{|u| u.id==params[:id]}.first
            error_out(404) if user.nil?

            if user.delete
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
