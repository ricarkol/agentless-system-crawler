# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
require 'fileutils'
require 'cgi'
require 'openid'
require 'openid/store/filesystem'

# Create openid tmp folder if necessary
openid_tmp = File.expand_path('../../../../tmp/openid', __FILE__)
unless File.exists? openid_tmp
  FileUtils.mkdir_p openid_tmp
end

# Set SSL CA list
OpenID.fetcher.ca_file = File.expand_path('../../../../config/ca.list', __FILE__)

module SentinelDocker
  module API
    class OpenID < Grape::API
      format :json
      default_format :json

      logger SentinelDocker::Log

      SREG = 'http://openid.net/sreg/1.0'

      helpers do
        def log
          SentinelDocker::Log
        end

        def session
          env['rack.session']
        end
      end

      before do
        @consumer ||= ::OpenID::Consumer.new(
          session,
          ::OpenID::Store::Filesystem.new(File.expand_path('../../../../tmp/openid', __FILE__))
        )
      end

      route :any, nil, anchor: false do
        # Complete or Begin?
        realm = params[:openid]
        openid_mode = params['openid.mode'.to_sym]

        home_url = "#{env['rack.url_scheme']}://#{env['HTTP_HOST']}"
        home_url << (env['HTTP_X_ORIGINAL_REQUEST_URI'] || env['REQUEST_URI'])

        if openid_mode
          # Complete OpenID Authentication
          params.delete('route_info')
          response = @consumer.complete(params, home_url)
          if response.status == ::OpenID::Consumer::SUCCESS
            identity = params['openid.identity'.to_sym]
            # Check if we know this user
            if SentinelDocker::Models::User.find(query: { identity: identity }).empty?
              log.info "Rejected login attempt from unknown identity: #{identity}"
              error! "#{identity} is not a known identity.", 401
            end
            log.info "Successful login attempt from known identity: #{identity}"

            session['identity'] = identity
            args = response.extension_response('sreg', false)
            session['fullname'] = args['fullname']
            session['email'] = args['email']

            # Redirect to original destination (remove openid param)
            destination = session['destination'] || '/web/docs/index.html'
            destination.sub!(/\??openid=[^&]+&?/, '')
            redirect destination
          else
            log.info response.message
            error! response.message, 401
          end
        else
          if realm && !SentinelDocker::Config.openid.realms.any? { |r| realm.start_with? r }
            log.info "Rejected login attempt made using unknown OpenID realm: #{realm}"
            error!("#{realm} was not a recognized OpenID realm", 403)
          elsif !realm
            if env['REQUEST_URI'].start_with? '/web/'
              realm = SentinelDocker::Config.openid.realms[0]
            else
              log.debug "Rejected unauthenticated access to api."
              error!("You need to authenticate to perform this operation.", 403)
            end
          end
          log.info "Received valid authentication request using recognized realm: #{realm}"

          # Begin OpenID Authentication
          begin
            response = @consumer.begin(realm)
          rescue ::OpenID::OpenIDError => e
            log.error e.to_s
            error! e.to_s, 401
          end
          response.add_extension_arg(SREG, 'required', 'email')
          response.add_extension_arg(SREG, 'optional', 'fullname')
          redirect_url = response.redirect_url(home_url, home_url)
          # Remember where we wanted to go in the first place
          session['destination'] = env['HTTP_X_ORIGINAL_REQUEST_URI'] || env['REQUEST_URI']
          redirect redirect_url
        end
      end
    end
  end
end
