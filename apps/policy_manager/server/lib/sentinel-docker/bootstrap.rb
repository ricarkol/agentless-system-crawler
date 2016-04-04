# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
module SentinelDocker
  module Bootstrap
    def self.os(system)
      const_get(system.os_type.capitalize)
    end

    def self.host(conf, user = nil, auto = true)
      conf = Hashie::Mash.new(conf)
      conf.delete(:id)
      user = conf.delete(:user) || 'root'
      password = conf.delete(:password)
      conf.user = Config.user

      # Sanitize system_group_ids
      if conf[:system_group_id]
        conf[:system_group_id] = Array(
          Models::SystemGroup.get(*Array(conf[:system_group_id]))).map(&:id)
      end

      system = Models::System.new(conf)

      # Bootstrap new system with Chef
      Util.with_clean_env do
        if auto
          if user.nil? || password.nil?
            fail "Both user and password need to be supplied. for #{conf}"
          end

          pubkey = IO.read("#{Config.ssh_key}.pub").chomp
          hidden_pass = "hidden_#{SecureRandom.hex(3)}"
          chef_server = Config.chef_server? ? "-s #{Config.chef_server} " : ''
          cmd = os(system).command(
            system, user, hidden_pass, chef_server, pubkey
          )

          Log.info "Bootstrapping system: #{cmd}"
          if user
            Log.info "Started by: #{user.respond_to?(:email) ? user.email : user}"
          end

          ENV[hidden_pass] = password
          output = `#{cmd}`
          ENV.delete(hidden_pass)

          unless $?.success?
            system.user = user
            system.password = password
            disavow(system, nokey: true)
            fail "Error bootstrapping system: #{system.as_json} #{output}"
          end
        else
          # register node and client on chef, but no knife boostrap is not called.
          cmd =
            "knife client create #{system.node_name} -d;"\
            " knife node create #{system.node_name} -d"
          knife_create_out = `#{cmd}`
          Log.info "Registering system without bootstrap: #{cmd}"
          unless $?.success?
            disavow(system, serveronly: true)
            fail "Error registering client and node #{system.node_name}"\
                 " #{knife_create_out}"
          end
        end
      end

      fail system.errors.full_messages.join(',') unless system.save
      system
    end

    def self.hosts(confs, max_thread = 5, user = nil, auto = true)
      confs = [confs] if confs.is_a? Hash
      return host(confs[0], user, auto) if confs.size == 1

      # rubocop:disable Lint/ShadowingOuterLocalVariable
      Thread.new(confs, max_thread) do |confs, max_thread|
        conf_queue = confs.dup
        while conf_queue.size > 0
          ts = []
          conf_queue.pop(max_thread).each do |conf|
            ts << Thread.new(conf) do |conf|
              begin
                # Bootstrap and then create the system
                Bootstrap.host(conf, user, auto)
              rescue => e
                Log.error e
              end
            end
          end
          ts.each(&:join)
        end
      end
      # rubocop:enable Lint/ShadowingOuterLocalVariable

      {
        message: 'The systems are being registered in the background.'\
                 ' They will show under /systems once registered.'
      }
    end

    def self.hosts_from_sl(ids, max_threads = 5, user = nil, auto = true)
      hosts(Array(ids).map { |id| load_from_sl(id) }, max_threads, user, auto)
    end

    def self.load_from_sl(id)
      server = nil
      begin
        server = SoftLayer::VirtualServer.server_with_id(id)
      rescue
        server = SoftLayer::BareMetalServer.server_with_id(id)
      end

      fail "System with id #{id} was not found on SoftLayer." if server.nil?

      # Get the credentials for a system
      creds = server['operatingSystem']['passwords'][0]

      if creds.nil?
        fail "System with id #{id} does not have associated credentials on SoftLayer."
      end

      {
        ip: server.primary_public_ip,
        hostname: server.fullyQualifiedDomainName,
        user: creds['username'],
        password: creds['password']
      }
    end

    def self.disavow(system, opts = {})
      Util.with_clean_env do
        `knife node delete #{system.node_name} -y`
        `knife client delete #{system.node_name} -y`

        ssh_cmd = os(system).disavow_command

        unless opts[:serveronly]
          if opts[:nokey]
            if system.os_type == 'linux'
              require 'net/ssh'
              Net::SSH.start(
                system.ip, system.user,
                port: system.port, password: system.password
              ) do |ssh|
                ssh.exec! ssh_cmd
              end
            else
              # TODO: Need to use winrm for Windows here
            end
          else
            ssh_cmd =
              "ssh -i #{Config.ssh_key} -p #{system.port}"\
              " #{system.user}@#{system.ip} #{ssh_cmd}"
            `#{ssh_cmd}`
          end
          Log.info "Removing ourselves from target system:\n#{ssh_cmd}"
        end

        ssh_host_name = Util.ssh_host(system)
        `ssh-keygen -R #{ssh_host_name}`
      end
    end

    def self.installer(system, temp_dir)
      os(system).installer(system, temp_dir)
    end
  end
end

require 'sentinel-docker/bootstrap/linux'
require 'sentinel-docker/bootstrap/windows'
