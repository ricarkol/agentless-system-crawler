# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
require 'hashie'
require 'logger'
require 'elasticsearch'

module SentinelDocker
  def self.load_config
    config_name = 'sentinel.yml'
    defaults = Hashie::Mash.new(
      limits: { max_images: 1000 },
      user: 'sentinel',
      ssh_key: '~/.ssh/id_rsa',
      log: { level: 'debug' },
      db: {
        limit: 1000,
        log: false,
        index_name: 'sentinel',
        hosts: [{ host: 'localhost', port: '9200' }]
      },
      openid: {
        enabled: true,
        realms: [
          'https://marketplace.ibmcloud.com/openid/id',
          'https://stage.marketplace-stage.ibmcloud.com/openid/id'
        ]
      }
    )
    config = defaults

    [
      "/etc/#{config_name}",
      File.join(ENV['HOME'], ".#{config_name}"),
      File.expand_path("../../../config/#{config_name}", __FILE__)
    ].each do |file|
      config = config.merge(YAML.load_file(file)) if File.exist? file
    end

    config
  end

  # Load sentinel config data
  Config = load_config

  # Expand ssh_key path
  Config.ssh_key = File.expand_path(Config.ssh_key)

  # Setup our logger
  Log = Logger.new(
    if Config.log? && Config.log.path
      f = File.open(Config.log.path, File::CREAT | File::WRONLY | File::APPEND)
      f.sync = true
      f
    else
      STDOUT.sync = true
      STDOUT
    end,

    if Config.log? && Config.log.age
      Config.log.age
    else
      'monthly'
    end
  )
  Log.level =
    if Config.log? && Config.log.level
      Logger.const_get(Config.log.level.upcase.to_sym)
    else
      Logger::INFO
    end

  # Load Elasticsearch client
  Store = Elasticsearch::Client.new(hosts: Config.db.hosts, log: Config.db.log)

  begin
    # Will raise an error if Elasticsearch is down, preventing the app from starting
    Store.info
  rescue
    errmsg = "Elasticsearch is not running! @ #{Config.db.hosts.map { |h| h.to_hash }}"
    Log.error(errmsg)
    $stdout.puts(errmsg)
    raise
  end

  # Create cache index
  begin
    Store.indices.create(index: Config.db.index_name)
    Log.info("Created main index '#{Config.db.index_name}'.")
  rescue
    Log.debug(
      "Did not have to create main index '#{Config.db.index_name}'. It already existed.")
  end
end
