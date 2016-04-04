# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
require 'active_model'
require 'active_support/core_ext/string/inflections'

I18n.enforce_available_locales = false

module SentinelDocker
  module Models
    class Base
      include ActiveModel::Model
      include ActiveModel::Serializers::JSON
      include ActiveModel::Validations

      class << self
        def attributes
          @attributes ||= []
        end

        def attr_accessor(*args)
          @attributes = attributes + args
          super(*args)
        end
      end

      attr_reader :attributes
      attr_accessor :id, :timestamp

      def initialize(attrs = {})
        attrs[:id] ||= nil

        self.class.attributes.each do |attribute|
          next if attrs.key?(attribute)
          attrs[attribute] = nil
        end

        # Add id fields used to manage relationships
        relation_attrs = {}
        self.class.relationships.each do |relation|
          next if relation[:type] == :has_many && relation[:opts][:dominant] != false
          relation_attrs["#{relation[:name].to_s.singularize}_id".to_sym] = nil
        end

        attrs = relation_attrs.merge(attrs)
        @attributes = attrs

        super
      end

      class << self
        def relationships
          @relationships ||= [] # { type: :has_many, name: :systems, opts: {...} }
        end

        def has_many(subject, args = {}) # rubocop:disable PredicateName
          relationships << { type: :has_many, name: subject, opts: args }

          if args[:dominant] == false
            many2many_key = "#{subject.to_s.singularize}_id".to_sym
            attr_accessor many2many_key

            define_method subject do |opts = {}|
              opts[:type] = __method__.to_s.singularize
              values = send("#{opts[:type]}_id") || []
              opts[:body] = { query: { ids: { values: values } } }
              self.class.find(opts)
            end

            define_method :add_to do |*peers|
              peers.each do |peer|
                foreign_key = "#{peer.class.model_name.element}_id"
                ids = send(foreign_key)
                if ids.nil?
                  ids = []
                  send("#{foreign_key}=", ids)
                end
                ids << peer.id unless ids.include? peer.id
              end
            end
          else
            define_method subject do |opts = {}|
              foreign_key = "#{self.class.model_name.element}_id".to_sym
              opts[:type] = __method__.to_s.singularize
              opts[:body] = { query: { match: { foreign_key => id } } }
              self.class.find(opts)
            end
          end
        end

        def belongs_to(subject)
          relationships << { type: :belongs_to, name: subject, opts: {} }

          foreign_key = "#{subject}_id".to_sym
          attr_accessor foreign_key

          define_method subject do |opts = {}|
            opts[:type] = __method__.to_s
            opts[:limit] = 1
            opts[:body] = { query: { match: { _id: send("#{__method__}_id") } } }
            self.class.find(opts)[0]
          end

          define_method :belongs_to do |owner|
            foreign_key = "#{owner.class.model_name.element}_id"
            send("#{foreign_key}=", owner.id)
          end
        end

        alias_method :has_one, :belongs_to

        def find(opts = {})
          # Make passing search options easier, without loosing the ability
          # to pass advanced options right into Elasticsearch's search method.
          if opts[:query]
            opts[:body] ||= {}
            if opts[:query].keys.size == 1
              opts[:body][:query] = { match: opts.delete(:query) }
            else
              clauses = []
              opts.delete(:query).each do |k, v|
                clauses << { match: { k => v } }
              end
              opts[:body][:query] = { bool: { must: clauses }}
            end
          end

          opts = {
            index: SentinelDocker::Config.db.index_name,
            type: model_name.element
          }.merge(opts)

          opts[:from] = opts.delete(:offset) if opts[:offset]
          opts[:size] = opts.delete(:limit) if opts[:limit]
          opts[:size] ||= SentinelDocker::Config.db.limit # TODO: find should get ALL, not just a limit.
          opts[:fields] = ['_source', '_timestamp']

          response = Hashie::Mash.new(SentinelDocker::Store.search(opts))
          results = response.hits.hits.map do |hit|
            klass = SentinelDocker::Models.const_get(opts[:type].camelize)
            #klass.new(hit._source.merge(id: hit._id))
            klass.new(hit._source.merge(id: hit._id, timestamp: hit.fields ? hit.fields._timestamp : nil))
          end

          # TODO: Rather create a class that inherits from Array to do this.
          # This adds methods for total, offset, and limit to the array.
          class << results
            [:total, :offset, :limit].each do |method|
              define_method "#{method}=" do |arg|
                instance_variable_set("@#{method}", arg) if arg
              end
              define_method method do
                instance_variable_get("@#{method}")
              end
            end
          end

          results.total = response.hits.total
          results.offset = opts[:from]
          results.limit = opts[:size]

          results
        end

        alias_method :all, :find

        def page(opts = {}) # TODO: turn this into an each-like enumerator
          opts[:offset] ||= 0
          opts[:limit] ||= SentinelDocker::Config.db.limit

          find(opts)
        end

        def get(*ids)
          results = find(body: { query: { ids: { values: ids } } })
          results = results[0] if ids.size == 1
          results
        end

        def do_mapping
          body = {
            "#{model_name.element}" => {
              '_timestamp' => {
                'enabled' => true, 'store' => true
              },
              'dynamic_templates' => [
                {
                  'strings_not_analyzed' => {
                    'match' => '*',
                    'match_mapping_type' => 'string',
                    'mapping' => {
                      'type' => 'string',
                      'index' => 'not_analyzed'
                    }
                  }
                }
              ]
            }
          }

          SentinelDocker::Store.indices.put_mapping(
            index: SentinelDocker::Config.db.index_name,
            type: model_name.element,
            body: body
          )
          SentinelDocker::Log.debug("Mapping for '#{model_name.element}' has been set.")
        end
      end

      def persisted?
        !id.nil? && !self.class.get(id).nil?
      end

      def save
        return false if invalid?

        if id || persisted?
          result = SentinelDocker::Store.update(
            index: SentinelDocker::Config.db.index_name,
            type: self.class.model_name.element,
            id: id,
            refresh: true,
            body: { doc: as_json, doc_as_upsert: true }
          )
        else
          result = SentinelDocker::Store.index(
            index: SentinelDocker::Config.db.index_name,
            type: self.class.model_name.element,
            refresh: true,
            body: as_json
          )
        end
        self.id = result['_id']
        # result = self.class.get(result['_id'])
        # self.timestamp = result['_timestamp']
        true
      end

      def update(attrs)
        attrs.keys.each do |key|
          receiver = "#{key.to_s}="
          send(receiver, attrs[key]) if respond_to?(receiver)
        end
      end

      def update!(attrs)
        update(attrs)
        save
      end

      def delete
        SentinelDocker::Store.delete(
          index: SentinelDocker::Config.db.index_name,
          type: self.class.model_name.element,
          refresh: true,
          id: id
        )

        manage_delete_relations

        true
      end

      private

      # rubocop:disable CyclomaticComplexity
      def manage_delete_relations
        # Manage relations
        # convert current class name into foreign id key
        foreign_key = "#{self.class.model_name.element}_id"
        self.class.relationships.each do |relation|
          next if relation[:type] != :has_many
          next if relation[:opts][:dominant] == false

          # convert relation name into elasticsearch type
          type = relation[:name].to_s.singularize

          # find all related items with the above two values (type and foreign_key)
          items = self.class.find(
            type: type, body: { query: { match: { foreign_key => id } } })
          
          # Do we have any belong_to only relations that we should also delete.
          delete_too = false
          if items.size > 0 && items[0].class.relationships.size > 0

            delete_too = items[0].class.relationships.all? do |r|
              #r[:type] == :belongs_to 
              r[:type] == :belongs_to || r[:type] == :has_many
            end
          end

          # for each, remove yourself from the list and save the item.
          items.each do |item|
            # remove from foreign_key if foreign key is an array
            foreign_key_value = item.send(foreign_key)
            if foreign_key_value.kind_of? Array
              foreign_key_value.delete(id)
              item.save
            # else just set the foreign_key to nil
            else
              # remove belong_to relations
              if delete_too
                item.delete
              else
                item.send("#{foreign_key}=", nil)
                item.save
              end
            end
          end
        end
      end
      # rubocop:enable CyclomaticComplexity
    end
  end
end
