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
    class Images < Grape::API
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
      resource :images, desc: 'Image registration and management' do

        # POST /images - Create image. Register a new node in Chef, and bootstrap the image.
        desc 'Register a new image', http_codes: {
          201 => 'Image successfully created.',
          303 => 'Partial image registration done. Follow redirect to complete registration manually.',
          400 => 'Bad request. Check request body.',
          403 => 'Registering these images will exceed the preconfigured maximum supported.'
        }, notes: 'Response headers: <br/><b>Location</b> header'\
                  ' indicating the URI of the newly registered image.<br/><br/>'\
                  'You can also post an array of images for bulk registration.'\
                  ' Bulk registration happens in the background however. The images'\
                  ' will show under <em>GET /images</em> once registered.'
        params do
          requires :body, type: Image::Entity, desc: 'A image representation', presence: false
          optional :install, type: String, param_type: 'query',
            desc: 'bootstrap image automatically or configure image manually?',
            default: 'auto', values: ['auto','manual']
        end
        post do
          error_out(400) unless env['api.request.body'].is_a?(Hash) || env['api.request.body'].is_a?(Array)

          install = params[:install]
          auto = (install == 'auto') ? true : false

          body = env['api.request.body']
          # Check max images limit
          size = body.is_a?(Array) ? body.size : 1
          total_images = Image.page(limit: 1).total
          if (total_images + size) > SentinelDocker::Config.limits.max_images
            error_out(403, "#{SentinelDocker::Config.limits.max_images} images supported."\
                           " There is a total of #{total_images} images registered."\
                           " #{size} incoming image(s) found in this request.")
          end

          #start bootstrap multiple hosts in parallel, and return before completion
          begin
            image = SentinelDocker::Bootstrap.hosts(body, 5, current_user, auto)
          rescue => exception
            error_out(400, exception)
          end

          if body.is_a?(Hash) || body.size == 1
            if auto
              header 'Location', "#{env['REQUEST_PATH']}/#{image.id}"
              present image
            else
              redirect "/api/images/#{image.id}/installer"
            end
          else
            image
          end
        end

        # GET /images - List out the images. Support paging.
        desc 'List the images', PAGE_OPTS.merge(
          entity: Image::Entity,
          is_array: true
        )
        get do
          images = Image.page(range(headers))
          set_page images
          present images
        end

        params do
          requires :id, type: String, desc: 'A image\'s id'
        end
        route_param :id do
          # PUT /image/{id} - Update a image.
          desc 'Update a image', http_codes: {
            200 => 'Image successfully updated.',
            400 => 'Bad request. Check request body.',
            404 => 'Not found. Image does not exist'
          }
          params do
            requires :body, type: Image::Entity, desc: 'A image representation', presence: false
          end
          put do
            error_out(400) unless env['api.request.body'].is_a?(Hash)
            id = params[:id]
            image = Image.get(id)
            error_out(404) if image.nil?

            body = Hashie::Mash.new(env['api.request.body'].merge(id: id))
            body.delete(:image_group_id)
            body.delete(:node_name)
            begin
              image.update(body)
              fail image.errors.full_messages.join(',') unless image.save
            rescue => exception
              error_out(400, exception)
            end

            present image
          end

          # GET /image/{id} - Show a image
          desc 'Show a image', entity: Image::Entity, http_codes: {
            200 => 'Success',
            404 => 'Not found. The image does not exist.'
          }
          get do
            image = Image.get(params[:id])
            error_out(404) if image.nil?
            present image
          end

          # DELETE /image/{id} - Delete a image. Remove node from chef
          desc 'Deregister a image', http_codes: {
            204 => 'Image successfully deleted.',
            404 => 'Not found. Image does not exist',
            500 => 'Error deleting the image.'
          }
          delete do
            image = Image.get(params[:id])
            error_out(404) if image.nil?

            Bootstrap.disavow(image)

            if image.delete
              status 204
              ''
            else
              error_out(500)
            end
          end

          # # GET /image/{id}/run - Run the rule in check or fix mode.
          # desc 'Run all image rules in their default mode', entity: ImageRule::Entity,
          # is_array: true, http_codes: {
          #   200 => 'Successful run.',
          #   204 => 'The image has no associated rules to run.',
          #   404 => 'Not found. The image does not exist.'
          # }
          # params do
          #   optional :use_period, type: Boolean,
          #     desc: 'Take the image group period interval into account?',
          #     default: 'false'
          # end
          # get 'run' do
          #   image = Image.get(params[:id])
          #   error_out(404, 'The image was not found.') if image.nil?

          #   image_rules = image.image_rules
          #   if image_rules.empty?
          #     status 204
          #     break ''
          #   end

          #   # Find current user
          #   user = current_user
          #   user = user.as_json if user

          #   break Util.run_image_rules(image, user) unless params[:use_period]

          #   # Find smallest period from all the image groups
          #   groups = image.image_groups
          #   memo = groups.size > 0 ? groups.first.period : 0
          #   period = image.image_groups.inject(memo) do |a, g|
          #     a = a.period if a.respond_to? :period
          #     g.period < a ? g.period : a
          #   end

          #   # Find the image rules that have not been run within the last period (hours)
          #   period = Time.now.to_i - (period.to_i * 3600) # convert to seconds ago
          #   due_rules = image_rules.select do |sp|
          #     sp.last_timestamp.nil? || sp.last_timestamp < period
          #   end

          #   Util.run_image_rules(due_rules, user) || ''
          # end

          # Add image rules api here
          # instance_eval(&SentinelDocker::API::ImageRules)

          # GET /images/{id}/compliance - Calculate a image's compliance
          desc 'Show compliance level of a image', http_codes: {
            200 => 'Success',
            404 => 'Not found. The image does not exist.'
          }, notes: 'Returns <em>true</em> if the image is compliant, and <em>false</em> otherwise.'\
                    '<br/>Compliance is calculated based on whether there all rules associated'\
                    ' with the image pass.'
          get 'compliance' do
            image = Image.get(params[:id]) or error_out(404)
            image.compliant?
          end
        end
      end
    end
  end
end
