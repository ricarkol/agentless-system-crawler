# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2015 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
require 'sentinel-docker/configuration'
require 'sentinel-docker/models/base'
#require 'sentinel-docker/models/containers'
require 'sentinel-docker/models/rules'
require 'sentinel-docker/models/users'
require 'sentinel-docker/models/configuration'

module SentinelDocker
  # Do additional model mapping configuration necessary on Elasticsearch
  Models.constants.each do |model|
#    next if model == :Base || model == :RuleAssign
    next if model == :Base
    model = Models.const_get(model)
    model.do_mapping
  end

  # Sync between configuration file data and configuration object in Elasticsearch
  configuration = Models::Configuration.get
  if configuration.nil?
    configuration = Models::Configuration.new(sl: Config.sl)
    configuration.save
  else
    Config.sl = configuration.sl
  end

  # Now that the configuration is properly loaded, init the SoftLayer client
  if Config.sl?
    SoftLayer::Client.default_client = SoftLayer::Client.new(
      username: Config.sl.username,
      api_key: Config.sl.api_key
    )
  end

  # Create default RuleGroup if it doesn't exist yet
  # Models::RuleGroup.new(name: 'default', id: 'default').save unless
  #   Models::RuleGroup.get('default')

  # # Sync policies over to our database - only if there are no polices to begin with
  # if Models::Policy.find(limit: 1).empty?
  #   Log.info 'Syncing policies. Please wait...'
  #   Util.with_clean_env do
  #     policy_lines = `knife cookbook list | egrep '^policy_'`.split("\n")
  #     if $?.success?
  #       policy_lines.each do |policy_line|
  #         policy_name, policy_version = policy_line.split(/[ ]+/)
  #         metadata = Util.get_policy_metadata(policy_name, policy_version)
  #         policy = Models::Policy.find(query: { name: policy_name })
  #         if policy.empty?
  #           Models::Policy.new(metadata).save
  #         else
  #           policy.first.update!(metadata)
  #         end
  #       end
  #       Log.info 'Ready'
  #     else
  #       Log.error "Could not get policies from chef server. #{policy_lines}"
  #     end
  #   end
  # end

  # Set up first user
  if Config.admin? && Models::User.find(query: { identity: Config.admin.identity }).empty?
    Models::User.new(Config.admin).save
  end
end
