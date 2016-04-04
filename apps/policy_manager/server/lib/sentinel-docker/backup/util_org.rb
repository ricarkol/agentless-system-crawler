# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
require 'zip'
require 'json'
require 'open3'

module SentinelDocker
  module Util
    def self.with_clean_env
      handler = proc do
        gemhome = ENV.delete('GEM_HOME')
        rubylib = ENV.delete('RUBYLIB')
        result = yield
        ENV['GEM_HOME'] = gemhome
        ENV['RUBYLIB'] = rubylib
        result
      end

      if defined? Bundler
        Bundler.with_clean_env(&handler)
      else
        handler.call
      end
    end

    def self.ssh_host(system)
      system.port == 22 ? system.ip : "'[#{system.ip}]:#{system.port}'"
    end

    def extract_files(policy_zip, target_dir)
      Zip::File.open(policy_zip) do |archives|
        base_dir = nil
        archives.each do |a|
          if a.name.end_with?('/metadata.rb')
            base_dir = File.dirname(a.name)
          end
        end

        if base_dir.nil?
          raise "The input file is not cookbook, does not have metadata.rb"
        end

        policy_name = File.basename(base_dir)
        unless policy_name.start_with?('policy_')
          raise "Policy name ''#{policy_name}'' has to start with \"policy_\""
        end

        #unzip files into target_dir
        base_path = Pathname.new(base_dir)

        archives.each do |a|
          path = Pathname.new(a.name)
          r_path = path.relative_path_from(base_path)
          extract_file = File.join(target_dir, r_path.to_s)
          if a.directory?
            Dir.mkdir(extract_file) unless File.exists?(extract_file)
          else
            File.open(extract_file, 'wb') do |fd|
              fd.write(a.get_input_stream.read)
            end
          end
        end

        policy_name
      end
    end

    def load_metadata(policy_name, policy_version)
      metadata = JSON.load(
        `knife cookbook show #{policy_name} #{policy_version} metadata -F json`,
        nil, symbolize_names: true
      )

      # filter out "recipes" attributes
      metadata[:attributes].each { |_, v| v.delete(:recipes) }

      {
        name: policy_name,
        version: metadata[:version],
        description: metadata[:description],
        long_description: metadata[:long_description],
        attrs: metadata[:attributes],
        platforms: metadata[:platforms],
        policy_group_id: ['default']
      }
    end

    def self.get_policy_metadata(policy_name, policy_version)
      self.instance_method(:load_metadata).bind(self).call(
        policy_name, policy_version)
    end

    def self.run_system_policies(system, user = nil)
      return unless system

      system_policies = system.is_a?(Array) ? system : system.system_policies
      return unless system_policies.size > 0

      batches = { check: {}, fix: {} }
      system_policies.each do |sp|
        batches[sp.auto_remedy == true ? :fix : :check][sp.policy] = sp
      end

      results = []
      batches.each do |k, v|
        unless v.empty?
          results += Array(run_policies(v, k, user))
        end
      end

      results
    end

    def self.run_policies(policies, mode = :check, user = nil)
      return if policies.nil? || policies.size < 1

      recipes = policies.keys.map do |p|
        "recipe[#{p.name}::default]"
      end.uniq.join(',')

      parameters = policies.keys.each_with_object({}) do |p, h|
        h[p.name] = p.parameters if p.parameters
      end

      system = policies.values.first.system

      # delete all node attributes persisted in chef-server before running policy
      Util.with_clean_env do
        knife_out =
          "knife exec -E 'n = nodes.find(\"name:#{system.node_name}\")[0];"\
          " if n; n.normal_attrs.clear; n.default_attrs.clear; n.save; end' 2>&1"
        `#{knife_out}`
        unless $?.success?
          fail "Error clearing node #{system.node_name} params before running"\
               "policies: #{knife_out}"
        end
      end

      cmd, args = Bootstrap.os(system).run_command(
        system, mode, parameters, recipes
      )

      Log.info "Running policy: #{cmd} #{args}"
      #output = `#{cmd} #{args}`
      _input, output, errput, thread = Open3.popen3("#{cmd} #{args}")
      thread.join
      output = output.read
      errput = errput.read
      #successful = process.value.exitstatus == 0

      # Parse json (whether fix or check mode).
      # If error (successful is false), everything fails
      begin
        parsed = JSON.parse(output)
        policy_map = policies.keys.each_with_object({}) { |p, h| h[p.name] = p }
        timestamp = Time.now.to_i
        parsed['policies'].each do |policy_result|
          next unless policy_map.key? policy_result['name']
          policy = policy_map[policy_result['name']]
          system_policy = policies[policy]
          policy_run = Models::PolicyRun.new(
            status:
              if mode == :check
                policy_result['fix_required'] == true ? 'FAIL' : 'PASS'
              else
                parsed['run_status'] == 'success' ? 'PASS' : 'FAIL'
              end,
            output: policy_result.to_json,
            mode: mode.to_s,
            timestamp: timestamp,
            user: user
          )
          policy_run.belongs_to(system_policy)
          policy_run.save
        end
      rescue JSON::ParserError
        timestamp = Time.now.to_i
        policies.keys.each do |policy|
          policy_run = Models::PolicyRun.new(
            status: 'FAIL',
            output: "#{output} #{errput}",
            mode: mode.to_s,
            timestamp: timestamp,
            user: user
          )
          policy_run.belongs_to(policies[policy])
          policy_run.save
        end
      end

      if policies.size == 1
        Models::SystemPolicy.get(policies.first.last.id)
      else
        Models::SystemPolicy.get(*(policies.values.map { |sp| sp.id }))
      end
    end
  end
end
