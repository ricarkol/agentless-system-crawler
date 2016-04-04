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
    class Configuration < Grape::API
      Config = ::SentinelDocker::Models::Configuration
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
      resource :configuration, desc: 'General configuration settings' do
        # GET /configuration
        desc 'Get this service\'s configuration', http_codes: {
          200 => 'Success'
        }, entity: Config::Entity
        get do
          present Config.get, with: Config::Entity
        end

        # PUT /configuration
        desc 'Update this service\'s configuration', http_codes: {
          200 => 'Configuration updated.',
          400 => 'Bad request. Check request body.'
        }
        params do
          requires :body, type: Config::Entity, desc: '', presence: false
        end
        put do
          error_out(400) unless env['api.request.body'].is_a? Hash
          body = Hashie::Mash.new(env['api.request.body'])
          conf = Config.get
          if conf.nil?
            conf = Config.new(body)
          else
            conf = Config.new(Hashie::Mash.new(conf.as_json).merge(body))
          end
          begin
            fail conf.errors.full_messages.join(',') unless conf.save
          rescue => exception
            error_out(400, exception)
          end
          SentinelDocker::Config.sl = conf.sl
          SoftLayer::Client.default_client = SoftLayer::Client.new(
            username: conf.sl.username,
            api_key: conf.sl.api_key
          )
          present conf, with: Config::Entity
        end
      end
    end
  end
end
