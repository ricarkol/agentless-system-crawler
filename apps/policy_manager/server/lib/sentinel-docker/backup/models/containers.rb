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
    class ContainerGroup < Base
      attr_accessor :name, :description, :period

      validates_presence_of :name

      has_many :containers

      def initialize(attrs = {})
        attrs[:period] ||= 0
        super(attrs)
      end

      def compliant?
        containers.all? { |s| s.compliant? }
      end

      class Entity < Grape::Entity
        expose :id, documentation: {
          type: 'string', desc: 'Container group ID (auto-generated)'
        }
        expose :name, documentation: {
          type: 'string', required: true, desc: 'Container group name'
        }
        expose :description, documentation: {
          type: 'string', desc: 'The Container group\'s description'
        }
        expose :period, documentation: {
          type: 'number', desc: 'The number of hours to wait before running the rules on the containers.'
        }
        expose :container_id, documentation: {
          type: 'array', desc: 'Array of container ids that has been created from this image (read-only)'
        }
      end
    end




    # class Image < Base
    #   attr_accessor :image_id, :image_name, :namespace, :created, :created_by, :created_from, :assigned
    #   validates_presence_of :namespace, :created
    #   has_many :containers
    #   has_many :image_rules
    #   belongs_to :rule_assign_group

    #   # validates_each :ip do |record, attr, value|
    #   #   found = record.class.find(query: { attr => value, :port => record.port })
    #   #   unless found.empty? || (found.size == 1 && found[0].id == record.id)
    #   #     record.errors.add attr, 'already being used with the same port.'
    #   #   end
    #   # end

    #   def initialize(attrs = {})
    #     super(attrs)
    #   end

    #   # def namespace
    #   #   "regcrawl-image-"+image.image_id
    #   # end

    #   def save

    #     result = super

    #     rule_map = {}

    #     unused_rule_assign_defs = []

    #     new_rule_ids = rule_assign_group.rules.map do |r|
    #       r.id
    #     end

    #     image_rules.each do |ir|
    #       rule_assign_def = ir.rule_assign_def
    #       if new_rule_ids.include? rule_assign_def.rule.id
    #         new_rule_ids.delete(rule_assign_def.rule.id)
    #       else
    #         unused_rule_assign_defs << rule_assign_def
    #       end
    #     end        

    #     unused_rule_assign_defs.each do |rule_assign_def|
    #       SentinelDocker::Log.error("fail to deleter rule_assign_def : #{rule_assign_def.id}") unless rule_assign_def.delete
    #     end

    #     new_rule_ids.each do |new_rule_id|
    #       rule_assign_def = RuleAssignDef.new
    #       new_rule = Rule.get(new_rule_id)
    #       rule_assign_def.belongs_to new_rule
    #       fail rule_assign_def.errors.full_messages.join(',') unless rule_assign_def.save
    #       image_rule = ImageRule.new
    #       image_rule.belongs_to self
    #       image_rule.belongs_to rule_assign_def
    #       fail image_rule.errors.full_messages.join(',') unless image_rule.save
    #     end
    #     result
    #   end


    #   class Entity < Grape::Entity
    #     expose :id, documentation: {
    #       type: 'string', desc: 'unique ID for container entity (auto-generated)'
    #     }
    #     expose :image_id, documentation: {
    #       type: 'string', desc: 'Image id', required: true
    #     }
    #     expose :image_name, documentation: {
    #       type: 'string', desc: 'Image name'
    #     }
    #     expose :namespace, documentation: {
    #       type: 'string', desc: 'namespace'
    #     }        
    #     expose :created, documentation: {
    #       type: 'integer',
    #       desc: 'The time container has created'
    #     }
    #     expose :created_by, documentation: {
    #       type: 'string',
    #       desc: 'The command to create this image'
    #     }
    #     expose :created_from, documentation: {
    #       type: 'string',
    #       desc: 'The image which this image is originated from'
    #     }        
    #     expose :rule_assign_group_id, documentation: {
    #       type: 'string',
    #       desc: 'The rule assign group id whiich this image belongs to'
    #     }
    #     expose :assigned, documentation: {
    #       type: 'integer',
    #       desc: 'The time the image has joined to the rule assign group'
    #     }
    #     # expose :container_id, documentation: {
    #     #   type: 'array', desc: 'Array of container ids that has been created from this image (read-only)'
    #     # }
    #   end
    # end


    class Container < Base
      attr_accessor :container_id, :container_name, :image_id, :created, :host_id

      validates_presence_of :container_id, :container_name, :image_id, :created

      has_one :image

      has_many :container_groups, dominant: false

      has_many :container_rules

      # validates_each :ip do |record, attr, value|
      #   found = record.class.find(query: { attr => value, :port => record.port })
      #   unless found.empty? || (found.size == 1 && found[0].id == record.id)
      #     record.errors.add attr, 'already being used with the same port.'
      #   end
      # end

      def initialize(attrs = {})
        super(attrs)
      end

      def save
        result = super
        image_rules = image.image_rules
        image_rules.each do |ir|
          rule_assign_def = ir.rule_assign_def
          cr = ContainerRule.new
          cr.belongs_to(self)
          cr.belongs_to(rule_assign_def)
          cr.save
        end
        result
      end

      def sync_rules
        ext_rule_assign_def_ids = container_rules.map do |cr|
          cr.rule_assign_def.id
        end
        image_rules = image.image_rules
        image_rules.each do |ir|
          rule_assign_def = ir.rule_assign_def
          next if ext_rule_assign_def_ids.include? rule_assign_def.id
          cr = ContainerRule.new
          cr.belongs_to(self)
          cr.belongs_to(rule_assign_def)
          cr.save
        end

      end

      def namespace
        "regcrawl-image-"+image.image_id+"/"+container_id[0..12]
      end

      def compliant?
        compliant = true

        container_rules.each do |cr|
          next if cr.last_status == 'PASS'

          if cr.last_status.nil?
            compliant = false
            break
          end

          r = cr.rule
          if r.grace_period.nil?
            compliant = false
            break
          end

          # sp.last_status is FAIL; are we within the grace period though?
          last_pass = ContainerRuleRun.find(limit: 1, query: { status: 'PASS', container_rule_id: cr.id }, sort: 'timestamp:desc')
          clauses = [{ match: { status: 'FAIL' } }, { match: { container_rule_id: cr.id } }]
          clauses << { range: { timestamp: { gte: last_pass[0].timestamp } } } unless last_pass.empty?
          first_fail = ContainerRuleRun.find(
            limit: 1,
            sort: 'timestamp:asc',
            body: { query: { bool: { must: clauses } } }
          ) # timestamp greater than last_pass, asc order, first one.


          if ((Time.now.to_i - first_fail[0].timestamp) / 86400.0) > p.grace_period.to_i
            compliant = false
            break
          end
        end

        compliant
      end

      class Entity < Grape::Entity
        expose :id, documentation: {
          type: 'string', desc: 'unique ID for container entity (auto-generated)'
        }
        expose :container_id, documentation: {
          type: 'string', desc: 'Container id', required: true
        }
        expose :container_name, documentation: {
          type: 'string', desc: 'Container name'
        }
        expose :image_id, documentation: {
          type: 'string', desc: 'The image id this container has been created from'
        }
        expose :created, documentation: {
          type: 'integer',
          desc: 'The time container has created'
        }
        expose :host_id, documentation: {
          type: 'string', required: true,
          desc: 'The host id this container is running on'
        }
        expose :container_group_id, documentation: {
          type: 'array', desc: 'Array of container groups ids that this container belongs to (read-only)'
        }
      end
    end

    class RuleRun < Base

      attr_accessor :status, :output, :mode, :timestamp, :user, :crawl_time, :namespace

      def initialize(attrs = {})
        if attrs[:user]
          attrs[:user] = attrs[:user].as_json.except('api_key')
        end
        super(attrs)
      end

      class Entity < Grape::Entity
        expose :id, documentation: {
          type: 'string', desc: 'Rule run ID (auto-generated)'
        }
        expose :status, documentation: {
          type: 'string', desc: 'Pass or fail status of the last check'
        }
        expose :output, documentation: {
          type: 'string', desc: 'Output of the last check or fix'
        }
        expose :mode, documentation: {
          type: 'string', desc: 'Check or fix mode run'
        }
        expose :timestamp, documentation: {
          type: 'integer', desc: 'Time of the rule run as an integer number of seconds since the Epoch.'
        }
        expose :crawl_time, documentation: {
          type: 'integer', desc: 'Time of collecting frame by crawler'
        }
        expose :namespace, documentation: {
          type: 'string', desc: 'cloudsight namespace of this container/image'
        }
        expose :user, documentation: {
          type: 'object', desc: 'User that ran the rule. Null if the run was done by the service.'
        }
        expose :rule_assign_id, documentation: {
          type: 'string', desc: 'Container rule that this run refers to'
        }
      end
    end


    class ContainerRuleRun < RuleRun

      attr_accessor :status, :output, :mode, :timestamp, :user, :crawl_time, :namespace
      belongs_to :container_rule
      validates_presence_of :status, :output, :mode, :timestamp, :crawl_time, :namespace, :container_rule_id

      def initialize(attrs={})
        super(attrs)
      end

      def save
        result = super
        cr = container_rule
        [:last_status, :last_output, :last_timestamp, :last_user].each do |field|
          cr.send("#{field}=", send(field.to_s.split('_').last))
        end
        cr.save

        result
      end

      class Entity < RuleRun::Entity
        expose :id, documentation: {
          type: 'string', desc: 'Rule run ID (auto-generated)'
        }
        expose :container_rule_id, documentation: {
          type: 'string', desc: 'Container rule that this run refers to'
        }
      end

    end

    class ImageRuleRun < RuleRun

      attr_accessor :status, :output, :mode, :timestamp, :user, :crawl_time, :namespace
      belongs_to :image_rule
      validates_presence_of :status, :output, :mode, :timestamp, :crawl_time, :namespace, :image_rule_id

      def initialize(attrs={})
        super(attrs)
      end

      def save
        result = super
        ir = image_rule
        [:last_status, :last_output, :last_timestamp, :last_user].each do |field|
          ir.send("#{field}=", send(field.to_s.split('_').last))
        end
        ir.save

        result
      end

      class Entity < RuleRun::Entity
        expose :id, documentation: {
          type: 'string', desc: 'Rule run ID (auto-generated)'
        }
        expose :image_rule_id, documentation: {
          type: 'string', desc: 'Image rule that this run refers to'
        }
      end

    end

    class RuleAssign < Base
      attr_accessor :last_status, :last_output, :last_timestamp, :last_user,
        :ignore_failure, :ignore_justification

      validate :justification_if_ignore

      # belongs_to :rule
      belongs_to :rule_assign_def

      def initialize(attrs={})
        super(attrs)
      end

      class Entity < Grape::Entity
        expose :last_status, documentation: {
          type: 'string', desc: 'Pass or fail status of the last run (read-only)'
        }
        expose :last_output, documentation: {
          type: 'string', desc: 'Output of the last run (read-only)'
        }
        expose :last_timestamp, documentation: {
          type: 'integer', desc: 'Time of the last run (read-only) as an integer number of seconds since the Epoch.'
        }
        expose :last_user, documentation: {
          type: 'object', desc: 'User that last ran the rule (read-only). Null if the run was done by the service.'
        }
        expose :ignore_failure, documentation: {
          type: 'boolean', desc: 'Ignore status when looking at overall container compliance'
        }
        expose :ignore_justification, documentation: {
          type: 'string', desc: 'Justification for ignoring status when looking at overall container compliance'
        }
        expose :rule_assign_def_id, documentation: {
          type: 'string', desc: 'Rule assignment definition that defines this rule assign', required: true
        }
      end

      def rule
        rule_assign_def ? rule_assign_def.rule : nil
      end

      private

      def justification_if_ignore
        errors.add(:base, 'A justification must be provided if this rule status should be ignored when considering compliance.') if ignore_failure && !ignore_justification
      end
    end

    class ContainerRule < RuleAssign

      attr_accessor :last_status, :last_output, :last_timestamp, :last_user,
        :ignore_failure, :ignore_justification

      RULE_RUN_CLASS = SentinelDocker::Models::ContainerRuleRun

      validates_presence_of :container_id, :rule_assign_def_id

      belongs_to :container
      belongs_to :rule_assign_def
      has_many :container_rule_runs

      def initialize(attrs={})
        super(attrs)
      end

      class Entity < RuleAssign::Entity
        expose :id, documentation: {
          type: 'string', desc: 'Container Rule ID (auto-generated)'
        }
        expose :container_id, documentation: {
          type: 'string', desc: 'Container that this container rule belongs to', required: true
        }
      end

    end

    class ImageRule < RuleAssign

      attr_accessor :last_status, :last_output, :last_timestamp, :last_user,
        :ignore_failure, :ignore_justification

      RULE_RUN_CLASS = SentinelDocker::Models::ImageRuleRun

      validates_presence_of :image_id, :rule_assign_def_id
      belongs_to :image
      belongs_to :rule_assign_def
      has_many :image_rule_runs

      def initialize(attrs={})
        super(attrs)
      end

      class Entity < RuleAssign::Entity
        expose :id, documentation: {
          type: 'string', desc: 'Image Rule ID (auto-generated)'
        }
        expose :image_id, documentation: {
          type: 'string', desc: 'Image that this image rule belongs to', required: true
        }
      end

    end

  end
end
