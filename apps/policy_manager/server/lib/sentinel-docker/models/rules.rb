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
    # class RuleGroup < Base
    #   attr_accessor :name, :description

    #   validates_presence_of :name

    #   has_many :rules

    #   def initialize(attrs = {})
    #     super(attrs)
    #   end

    #   class Entity < Grape::Entity
    #     expose :id, documentation: {
    #       type: 'string', desc: 'Rule group ID (auto-generated)'
    #     }
    #     expose :name, documentation: {
    #       type: 'string', required: true, desc: 'Rule group name'
    #     }
    #     expose :description, documentation: {
    #       type: 'string', desc: 'The Rule group\'s description'
    #     }
    #   end
    # end

    class Rule < Base
      attr_accessor :name, :script_path, :version, :description, :long_description, :attrs,
        :platforms, :parameters, :grace_period, :rule_group_name

      belongs_to :tenant
      validates_presence_of :name, :tenant
      has_many :groups, dominant: false

      validate :unique_name_in_tenant

      def unique_name_in_tenant
        begin
          found = self.class.find(query: { :name => name, :tenant_id => tenant.id })
        rescue Elasticsearch::Transport::Transport::Error
        end
        unless found.empty? || (found.size == 1 && found[0].id == id)
          errors.add name, 'already being used in a rule.'
        end
      end

      def initialize(attrs = {})
        super(attrs)
      end

      class Entity < Grape::Entity
        expose :id, documentation: {
          type: 'string', desc: 'Rule ID (alias to the name)'
        }
        expose :name, documentation: {
          type: 'string', required: true,
          desc: 'Rule name (must match the cookbook name this is associated to)'
        }
        expose :script_path, documentation: {
          type: 'string', desc: 'Script path'
        }
        expose :version, documentation: {
          type: 'string', desc: 'The version number of this rule'
        }
        expose :description, documentation: {
          type: 'string', desc: 'Rule description'
        }
        expose :long_description, documentation: {
          type: 'string', desc: 'Rule documentation'
        }
        expose :attrs, documentation: {
          type: 'string', desc: 'Accepted attributes for this rule'
        }
        expose :platforms, documentation: {
          type: 'string', desc: 'Platforms supported by this rule'
        }
        expose :parameters, documentation: {
          type: 'object', desc: 'Rule parameters (JSON-formatted)'
        }
        expose :grace_period, documentation: {
          type: 'integer',
          desc: 'Grace period (in days) before a container is considered uncompliant due to rule failure'
        }
        expose :tenant_id, documentation: {
          type: 'string', desc: 'Tenant ID'
        }
        expose :group_id, documentation: {
          type: 'array', desc: 'groups id that this rule belongs to (read-only)'
        }
        expose :rule_group_name, documentation: {
          type: 'string', desc: 'rule group name that this rule belongs to'
        }
        expose :timestamp, documentation: {
          type: 'integer', desc: 'Time of the last update of this rule as an integer number of seconds since the Epoch.'
        }
      end
    end

    class Tenant < Base

      attr_accessor :name, :owner_namespaces

      has_many :users
      has_many :groups
      has_many :rules
      has_many :images

      validates_presence_of :name

      def initialize(attrs = {})
        super(attrs)
      end

      def default_group
        groups.select { |g| g.default == true }.first
      end

      def group_by_name(name)
        groups.select { |g| g.name == name }.first
      end

      def group_by_id(group_id)
        groups.select { |g| g.id == group_id }.first
      end

      def image(namespace)
        images.select { |img| img.namespace == namespace }.first
      end

      class Entity < Grape::Entity
        expose :id, documentation: {
          type: 'string', desc: 'Tenant ID (auto-generated)'
        }
        expose :name, documentation: {
          type: 'string', required: true, desc: 'Tenant Name'
        }
        expose :owner_namespaces, documentation: {
          type: 'array', desc: 'Owner namespaces which belong to this tenant'
        }
        expose :user_id, documentation: {
          type: 'array', desc: 'Array of user ids which belongs to this tenant (read-only)'
        }
        expose :group_id, documentation: {
          type: 'array', desc: 'Array of group ids which belongs to this tenant (read-only)'
        }
        expose :rule_id, documentation: {
          type: 'array', desc: 'Array of rule ids which belongs to this tenant (read-only)'
        }
        expose :image_id, documentation: {
          type: 'array', desc: 'Array of image ids which belongs to this tenant (read-only)'
        }
      end

    end

    class Group < Base

      attr_accessor :name, :default, :auto_assign

      has_many :images
      has_many :rules, dominant: false
      belongs_to :tenant

      validates_presence_of :name, :tenant
      validate :tenant_consistency

      def tenant_consistency
        if rules
          rules.each do |r|
            errors.add "rule #{r.name} is not defined for tenant #{tenant.name}" unless r.tenant.id == tenant.id
          end
        end
      end

      def initialize(attrs = {})
        attrs[:default] ||= false
        super(attrs)
      end

      class Entity < Grape::Entity
        expose :id, documentation: {
          type: 'string', desc: 'Group ID (auto-generated)'
        }
        expose :name, documentation: {
          type: 'string', required: true, desc: 'Rule Assign Group Name'
        }
        expose :default, documentation: {
          type: 'boolean', desc: 'use as default group'
        }
        expose :tenant_id, documentation: {
          type: 'string', desc: 'Tenant ID which this group is defined for (read-only)'
        }
        expose :rule_id, documentation: {
          type: 'array', desc: 'Array of rule ids which belongs to this group'
        }
        expose :auto_assign, documentation: {
          type: 'object', desc: 'auto assignment configuration (JSON-formatted)'
        }
      end

      def save
        fail 'tenant unset' unless tenant 
        if default
          default_groups = self.class.find(query: {tenant_id: tenant.id, default: true})
          default_groups.each do |g|
            next if id && g.id == id
            g.default = false
            fail g.full_messages.join(',') unless g.save
          end
        end
        super
        rules.each do |r|
          if r.groups.select{ |g| g.id == id }.empty?
            arr = r.groups.map{|g| g.id} || []
            arr << id
            r.group_id = arr
            r.save
          end
        end
      end

    end

    class Image < Base
      attr_accessor :name, :namespace, :owner_namespace, :system_type, :first_crawled, :created, :assigned

      belongs_to :group
      belongs_to :tenant

      validates_presence_of :name, :namespace, :tenant

      # validates_each :ip do |record, attr, value|
      #   found = record.class.find(query: { attr => value, :port => record.port })
      #   unless found.empty? || (found.size == 1 && found[0].id == record.id)
      #     record.errors.add attr, 'already being used with the same port.'
      #   end
      # end

      validate :unique_namespace

      def unique_namespace
        begin
          found = self.class.find(query: { namespace: namespace })
        rescue Elasticsearch::Transport::Transport::Error
        end
        unless found.empty? || (found.size == 1 && found[0].id == id)
          errors.add name, 'already being used in a rule.'
        end
      end

      def initialize(attrs = {})
        super(attrs)
      end

      class Entity < Grape::Entity
        expose :id, documentation: {
          type: 'string', desc: 'unique ID for container entity (auto-generated)'
        }
        expose :name, documentation: {
          type: 'string', desc: 'Image name'
        }
        expose :namespace, documentation: {
          type: 'string', desc: 'namespace'
        }        
        expose :owner_namespace, documentation: {
          type: 'array', desc: 'array of owner namespaces'
        }
        expose :system_type, documentation: {
          type: 'string',
          desc: 'system type'
        }
        expose :first_crawled, documentation: {
          type: 'integer',
          desc: 'first_crawled'
        }
        expose :created, documentation: {
          type: 'integer',
          desc: 'The time the image has created'
        }
        expose :assigned, documentation: {
          type: 'integer',
          desc: 'The time the image has joined to the group'
        }
        expose :group_id, documentation: {
          type: 'string',
          desc: 'The group id whiich this image belongs to'
        }
        expose :tenant_id, documentation: {
          type: 'string',
          desc: 'The tenant id whiich this image belongs to'
        }
      end
    end


  end
end
