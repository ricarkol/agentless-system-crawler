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
    class CandidateSystems < Grape::API
      include SentinelDocker::Models
      DESCRIPTIONS = ::SentinelDocker::API::DESCRIPTIONS

      prefix 'api'
      format :json
      default_format :json

      class Entity < Grape::Entity
        expose :id, documentation: {
          type: 'string', desc: 'Candidate System ID', required: true
        }
        expose :ip, documentation: {
          type: 'string', desc: 'IP Address', required: true
        }
        expose :hostname, documentation: {
          type: 'string', desc: 'System hostname or nickname', required: true
        }
        expose :datacenter, documentation: {
          type: 'string', desc: 'Datacenter where server is located', required: true
        }
        expose :type, documentation: {
          type: 'string', desc: 'VirtualServer or BareMetalServer', required: true
        }
      end

      params do
        optional :api_key, type: String, param_type: 'query',
          desc: DESCRIPTIONS[:api_key]
        optional :openid, type: String, param_type: 'query',
          desc: DESCRIPTIONS[:openid]
      end
      resource :candidate_systems, desc: 'SoftLayer systems to register' do

        # GET /candidate_systems - List out the candidate systems.
        desc 'List the systems', entity: Entity, is_array: true, http_codes: {
          200 => 'Success.',
          500 => 'Error retrieving candidate servers from SoftLayer.'
        }, notes: 'You need to set SoftLayer credentials in the <em>/configuration</em>'\
                  ' api for this call to work.'
        get do
          servers = []
          handler = proc do |server|
            servers << {
              id: server.id,
              ip: server.primary_public_ip,
              hostname: server.fullyQualifiedDomainName,
              datacenter: server.datacenter['longName'],
              type: server.class.name
            }
          end

          begin
            SoftLayer::BareMetalServer.find_servers.each(&handler)
            SoftLayer::VirtualServer.find_servers.each(&handler)
          rescue => e
            msg = e.to_s
            msg += ' Did you configure SoftLayer credentials?' if msg == 'Invalid API token.'
            error!(msg, 500)
          end

          servers
        end

        # POST /candidate_systems/{id} - Pick a system(s) for registration
        desc 'Pick a candidate system(s) for registration', http_codes: {
          200 => 'System(s) successfully registered.',
          400 => 'Bad request. Check system parameters.',
          404 => 'Not found. System does not exist'
        }, notes: 'The <em>id</em> may also be a comma-delimited list of IDs to'\
                  ' register multiple systems. If registering multiple systems, '\
                  'the action will be performed in the background. The systems'\
                  ' will show under <em>GET /systems</em> once registered.<br/>'\
                  'Response headers: <br/><b>Location</b> header'\
                  ' indicating the URI of the newly registered system.'
        params do
          requires :id, type: String, desc: 'A candidate system softlayer id'
        end
        post ':id' do
          # Get system by id, then do a post on systems, with information.

          # First, accept a comma-delimited list of ids
          ids = params[:id].split(/,/).map { |i| i.to_i }

          begin
            # Bootstrap single host and then create the system synchronously
            SentinelDocker::Bootstrap.hosts_from_sl(ids)
          rescue => exception
            error_out(400, exception)
          end
        end
      end
    end
  end
end
