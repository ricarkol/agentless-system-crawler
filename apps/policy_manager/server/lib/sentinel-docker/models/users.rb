# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
require 'securerandom'

module SentinelDocker
  module Models
    class User < Base
      attr_accessor :identity, :fullname, :email, :api_key

      belongs_to :tenant

      validates_presence_of :identity

      validates_each :identity do |record, attr, value|
        found = record.class.find(query: { attr => value })
        unless found.empty? || (found.size == 1 && found[0].id == record.id)
          record.errors.add attr, 'already being used by a user.'
        end
      end

      def initialize(attrs = {})
        attrs[:api_key] ||= SecureRandom.hex(32)
        super(attrs)
      end

      class Entity < Grape::Entity
        expose :id, documentation: {
          type: 'string', desc: 'User ID (auto-generated)'
        }
        expose :identity, documentation: {
          type: 'string', desc: 'OpenID Identity URI', required: true
        }
        expose :fullname, documentation: {
          type: 'string', desc: 'User\'s full name'
        }
        expose :email, documentation: {
          type: 'string', desc: 'User\'s e-mail'
        }
        expose :api_key, documentation: {
          type: 'string', desc: 'User\'s api key'
        }, if: lambda { |user, opts| opts[:user].respond_to?(:id) ? user.id == opts[:user].id : true }
        expose :tenant_id, documentation: {
          type: 'string', desc: 'Tenant ID'
        }
      end
    end
  end
end
