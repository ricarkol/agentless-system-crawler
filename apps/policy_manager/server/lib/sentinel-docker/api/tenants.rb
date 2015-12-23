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
    class Tenants < Grape::API
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
      resource :tenants, desc: 'Tenants' do
        # POST /tenants
        desc 'Create a new tenant', entity: Tenant::Entity, http_codes: {
          201 => 'Tenant successfully created.',
          400 => 'Bad request. Check request body.', 
          401 => 'Authentication required.',
          403 => 'Forbidden - unauthorized request'
        }, notes: 'Response headers: <br/><b>Location</b> header'\
          ' indicating the URI of the newly created tenant.'
        params do
          requires :body, type: Tenant::Entity, desc: 'A tenant representation', presence: false
        end
        post do
          error_out(401, "authentication required") unless current_user
          error_out(403, 'unauthorized operation') unless current_user.tenant.name == 'IBM'

          error_out(400) unless env['api.request.body']
          error_out(400, 'A JSON object is required. Found an array.') unless env['api.request.body'].is_a? Hash
          error_out(400, 'name must be specified') unless env['api.request.body']['name']
          body = Hashie::Mash.new(env['api.request.body'])
          body.delete(:id)
          error_out(400, "tenant #{body.name} already exists") unless Tenant.find(query: { 'name' => body.name }).empty?

          begin
            tenant = Tenant.new(body)
            fail tenant.errors.full_messages.join(',') unless tenant.save
          rescue => exception
            error_out(400, exception)
          end
          header 'Location', "#{env['REQUEST_PATH']}/#{tenant.id}"
          tenant
        end

        # GET /tenants
        desc 'List the tenants', PAGE_OPTS.merge(
          entity: Tenant::Entity, is_array: true, http_codes: {
            200 => 'Container group successfully updated.',
            400 => 'Bad request. Check request body.',
            401 => 'Authentication required.',
            403 => 'Forbidden - unauthorized request',
            404 => 'Not found. The tenant does not exist.'
          }
        )
        get do
          error_out(401, "authentication required") unless current_user
          error_out(403, 'unauthorized operation') unless current_user.tenant.name == 'IBM'
          params.update(range(headers))
          tenants = Tenant.page(offset: params[:offset], limit: params[:limit])
          set_page tenants
        end

        params do
          requires :id, type: String, desc: 'A tenant id'
        end
        route_param :id do
          # PUT /tenants/{id}
          desc 'Update a tenant', entity: Tenant::Entity, http_codes: {
            200 => 'Container group successfully updated.',
            400 => 'Bad request. Check request body.',
            401 => 'Authentication required.',
            403 => 'Forbidden - unauthorized request',
            404 => 'Not found. The tenant does not exist.'
          }
          params do
            requires :body, type: Tenant::Entity, desc: 'A tenant representation', presence: false
          end
          put do
            error_out(401, "authentication required") unless current_user
            error_out(403, 'unauthorized operation') unless current_user.tenant.name == 'IBM'
            error_out(400) unless env['api.request.body'].is_a?(Hash)
            id = params[:id]
            tenant = Tenant.get(id)
            error_out(404) if tenant.nil?

            body = Hashie::Mash.new(env['api.request.body'])
            body.delete(:id)
            body.delete(:group_id)
            begin
              tenant.update(body)
              fail tenant.errors.full_messages.join(',') unless tenant.save
            rescue => exception
              error_out(400, exception)
            end
            tenant
          end

          # GET /tenants/{id}
          desc 'Show a tenant', entity: Tenant::Entity, http_codes: {
            200 => 'Success',
            401 => 'Authentication required.',
            403 => 'Forbidden - unauthorized request',
            404 => 'Not found. The tenant does not exist.'
          }
          get do
            error_out(401, "authentication required") unless current_user
            user = current_user
            error_out(403, 'unauthorized operation') unless user.tenant.name == 'IBM' || user.tenant.id == params[:id]
            Tenant.get(params[:id]) || error_out(404)
          end

          # DELETE /tenants/{id}
          desc 'Delete a tenant', http_codes: {
            204 => 'Tenant successfully deleted.',
            401 => 'Authentication required.',
            403 => 'Forbidden - unauthorized request',
            404 => 'Not found. The tenant does not exist.',
            500 => 'Error deleting the tenant.'
          }
          delete do
            error_out(401, "authentication required") unless current_user
            error_out(403, 'unauthorized operation') unless current_user.tenant.name == 'IBM'
            error_out(500) unless params[:id]
            t = Tenant.get(params[:id])
            error_out(404) unless t

            if t.delete
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
