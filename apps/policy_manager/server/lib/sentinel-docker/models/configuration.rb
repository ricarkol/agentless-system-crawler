# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
module SentinelDocker
  module Models
    class Configuration < Base
      attr_accessor :sl

      def self.get
        Configuration.all[0]
      end

      class Entity < Grape::Entity
        expose :sl, documentation: {
          type: 'object', desc: 'SoftLayer credentials object '\
                                '(ex. { username: \'\', api_key: \'\' })'
        }
      end
    end
  end
end
