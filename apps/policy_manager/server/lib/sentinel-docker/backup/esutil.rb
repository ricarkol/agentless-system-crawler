require 'sentinel-docker'
require 'sentinel-docker/docker_util'
require 'parallel'

module SentinelDocker
  module ESUtil

    Log = SentinelDocker::Log

    Config = Hashie::Mash.new(
      local_es_host: 'elasticsearch',
      local_es_port: '9200',
      local_es_log_enabled: false,
      max_return: 1000
    )

    Store = Elasticsearch::Client.new(hosts: [{ host: "#{Config.local_es_host}", port: "#{Config.local_es_port}" }], log: Config.local_es_log_enabled)

    def self.find(index, type, opts = {})

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
        index: index,
        type: type
      }.merge(opts)

      opts[:body][:sort] = opts.delete(:sort) if opts[:sort]
      opts[:from] = opts.delete(:offset) if opts[:offset]
      opts[:size] = opts.delete(:limit) if opts[:limit]
      opts[:size] ||= Config.max_return

      response = Hashie::Mash.new(Store.search(opts))
      results = response.hits.hits.map do |hit|
        hit._source.merge(id: hit._id)
      end

    end

    def self.get(index, type, id)
      param = {
        index: Config.local_job_index,
        type: type,
        body: {
          query: {
            ids: { values: [id] }
          }
        }
      }

      response = Hashie::Mash.new(Store.search(param))
      results = response.hits.hits.map do |hit|
        hit._source.merge(id: hit._id)
      end
      results.first
    end

    def self.put(index, type, doc)

      result = Store.index(
        index: index,
        type: type,
        refresh: true,
        body: doc
      )
      result['_id']

    end

    def self.update(index, type, id, doc)

      result = Store.update(
        index: index,
        type: type,
        id: id,
        refresh: true,
        body: { doc: doc, doc_as_upsert: true }
      )

      result

    end

    def self.delete(index, type, id)

      SentinelDocker::Store.delete(
        index: index,
        type: type,
        refresh: true,
        id: id
      )

    end

  end
end

