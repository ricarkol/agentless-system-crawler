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
    ImageRules = proc do
      Image = SentinelDocker::Models::Image
      ImageRule = SentinelDocker::Models::ImageRule
      ImageRuleRun = SentinelDocker::Models::ImageRuleRun

      resource :rules do

        # POST /image_rules - Create image rule.
        desc 'Create a new image rule', entity: ImageRule::Entity, http_codes: {
          201 => 'Image rule successfully created.',
          400 => 'Bad request. Check request body.',
          404 => 'Not found. Image does not exist.'
        }, notes: 'Response headers: <br/><b>Location</b> header'\
                  ' indicating the URI of the newly registered image rule.'
        params do
          requires :body, type: ImageRule::Entity, desc: 'A image rule representation',
            presence: false
        end
        post do
          error_out(401) unless env['api.request.body'].is_a?(Hash)
          image_id = params[:id]
          error_out(404) if Image.get(image_id).nil?
          body = Hashie::Mash.new(env['api.request.body'])
          body.reject! { |k| %w(id last_status last_output last_user last_timestamp).include? k }
          body[:image_id] = image_id
          begin
            image_rule = ImageRule.new(body)
            fail 'Bad rule_assign_def_id' unless image_rule.rule_assign_def
            fail image_rule.errors.full_messages.join(',') unless image_rule.save
          rescue => exception
            error_out(400, exception)
          end
          header 'Location', "#{env['REQUEST_PATH']}/#{image_rule.id}"
          image_rule
        end

        # GET /image_rules - List out the image rules. Support paging.
        desc 'List the image rules', PAGE_OPTS.merge(
          entity: ImageRule::Entity,
          is_array: true,
          http_codes: { 404 => 'Not found. Image does not exist.' }
        )
        get do
          error_out(404) if Image.get(params[:id]).nil?
          params.update(range(headers))
          image_rules = ImageRule.page(
            offset: params[:offset], limit: params[:limit], query: { image_id: params[:id] })
          set_page image_rules
        end

        params do
          requires :image_rule_id, type: String, desc: 'A image rule id'
        end
        route_param :image_rule_id do
          # PUT /image_rules/{id} - Update a image rule.
          desc 'Update a image rule', entity: ImageRule::Entity, http_codes: {
            200 => 'Image rule successfully updated.',
            400 => 'Bad request. Check request body.',
            404 => 'Not found. The image rule does not exist.'
          }, notes: 'You can only update <em>auto_remedy</em>, <em>ignore_failure</em>,'\
                    ' and <em>ignore_justification</em>.'
          params do
            requires :body, type: ImageRule::Entity, desc: 'A image rule representation',
              presence: false
          end
          put do
            error_out(400) unless env['api.request.body'].is_a?(Hash)
            error_out(404, 'The image was not found.') if Image.get(params[:id]).nil?
            id = params[:image_rule_id]
            image_rule = ImageRule.get(id)
            error_out(404, image_rule.as_json) if image_rule.nil? || image_rule.image_id != params[:id]

            body = Hashie::Mash.new(env['api.request.body'])
            body.reject! { |k| %w(id image_id "rule_assign_def_id last_timestamp last_output last_status last_user).include? k }
#            error_out(400, body)

            begin
              image_rule.update(body)
              fail image_rule.errors.full_messages.join(',') unless image_rule.save
            rescue => exception
              error_out(400, exception)
            end
            image_rule
          end

          # GET /image_rules/{id} - Show a image rule
          desc 'Show a image rule', entity: ImageRule::Entity, http_codes: {
            200 => 'Success',
            404 => 'Not found. The image rule does not exist.'
          }
          get do
            image = Image.get(params[:id])
            error_out(404, 'The image was not found.') if image.nil?
            image_rule = ImageRule.get(params[:image_rule_id])
            error_out(404) if image_rule.nil? || image_rule.image_id != image.id
            image_rule
          end

          # DELETE /image_rules/{id} - Delete a image rule. Remove node from chef
          desc 'Delete a image rule', http_codes: {
            204 => 'Image rule successfully deleted.',
            404 => 'Not found. The image rule does not exist.',
            500 => 'Error deleting the image rule.'
          }
          delete do
            image = Image.get(params[:id])
            error_out(404, 'The image was not found.') if image.nil?

            image_rule = ImageRule.get(params[:image_rule_id])
            error_out(404) if image_rule.nil? || image_rule.image_id != image.id

            if image_rule.delete
              status 204
              ''
            else
              error_out(500)
            end
          end

          # GET /image_rules/{id}/run - Run the rule in check or fix mode.
          desc 'Run a image rule in check or fix mode', entity: ImageRule::Entity, http_codes: {
            200 => 'Successful run.',
            404 => 'Not found. The image rule does not exist.',
            400 => 'Bad request. Check that the mode parameter is either "fix" or "check".',
            500 => 'An internal error was encountered'
          }
          params do
            optional :mode, type: String, desc: 'Run this in fix or check mode',
              values: %w(check fix)
          end
          get 'run' do
            image = Image.get(params[:id])
            error_out(404, 'The image was not found.') if image.nil?

            id = params[:image_rule_id]

            image_rule = ImageRule.get(id)
            error_out(404) if image_rule.nil? || image_rule.image_id != image.id

            rule = image_rule.rule
            error_out(404, 'Related rule does not exist.') if rule.nil?

            # Find current user
            user = current_user
            user = user.as_json if user

            DockerUtil.run_rule(image_rule, user)
          end

          # GET /image_rules/{id}/runs - List out the image rule runs. Support paging.
          desc 'List the previous image rule runs', PAGE_OPTS.merge(
            entity: ImageRuleRun::Entity,
            is_array: true,
            http_codes: { 404 => 'Not found' }
          )
          params do
            optional :mode, type: String, desc: 'Filter on run mode (check or fix)',
              values: %w(check fix)
          end
          get 'runs' do
            image = Image.get(params[:id])
            error_out(404, 'The image was not found.') if image.nil?

            params.update(range(headers))
            id = params[:image_rule_id]
            mode = params[:mode]

            image_rule = ImageRule.get(id)
            error_out(404, 'The rule was not found.') \
              if image_rule.nil? || image_rule.image_id != image.id

            query = { image_rule_id: id }
            query.update(mode: mode) if mode

            rule_runs = ImageRuleRun.page(
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
