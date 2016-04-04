# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
module SentinelDocker
  module Rack
    class Doorman
      def initialize(app)
        @app = app
      end

      def call(env)
        passthru = false
        req = ::Rack::Request.new(env)
        session = req.session

        passthru = true unless SentinelDocker::Config.openid.enabled
        passthru = true if ['localhost', '127.0.0.1'].include? env['SERVER_NAME']

        unless passthru
          api_key = req.GET['api_key']
          if api_key && !SentinelDocker::Models::User.find(query: { api_key: api_key }).empty?
            passthru = true
          end
        end

        # Go through OpenID flow if there is no session found
        unless passthru || session['identity']
          return SentinelDocker::API::OpenID.call(env)
        end

        @app.call(env)
      end
    end
  end
end
