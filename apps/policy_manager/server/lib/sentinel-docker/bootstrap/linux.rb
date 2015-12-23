# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2015 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
require 'securerandom'
require 'erubis'
require 'json'
require 'tmpdir'
require 'zip'

module SentinelDocker
  module Bootstrap
    module Linux
      def self.command(system, user, pass, chef_server, pubkey)
        "knife bootstrap #{system.ip} #{chef_server}-p #{system.port}"\
        " -x #{user} -P $#{pass} -N #{system.node_name}"\
        " -r 'recipe[sentinel_bootstrap]' --sudo"\
        " -j '{\"sentinel_bootstrap\":{\"public_key\":\"#{pubkey}\"}}'"\
        " --bootstrap-version #{CHEF_VERSION}"\
        " --distro chef-sentinel 2>&1"
      end

      def self.disavow_command
        'sudo rm -rf /etc/sentinel /var/sentinel /var/log/sentinel'\
        ' /var/run/sentinel /var/lib/sentinel /var/cache/sentinel'
      end

      def self.run_command(system, mode, parameters, recipes)
        tmpfilename = "/tmp/sentinel.chef.#{SecureRandom.hex}"

        cmd =
          "ssh -i #{Config.ssh_key} -p #{system.port}"\
          " #{system.user}@#{system.ip} \""
        cmd += %{echo '#{parameters.to_json.gsub(/"/, '\"')}' > #{tmpfilename} && }
        cmd += "sudo chef-client"
        args =
          "-c /etc/sentinel/client.rb #{mode == :check ? '-W' : ''}"\
          " -j #{tmpfilename} -o \\\"#{recipes}\\\" --no-color\""

        [cmd, args]
      end

      def self.installer(system, temp_dir)
        pubkey_path = "#{Config.ssh_key}.pub"
        node_name = system.node_name
        script_dir = '/opt/ibm/sentinel/scripts'
        template_file_path = File.join(
          ENV['HOME'], '.chef', 'bootstrap', 'chef-sentinel.erb')

        # client key gen
        temp_key_path = File.join(temp_dir, 'client.pem')

        Util.with_clean_env do
          # reregister key
          cmd = "knife client reregister #{node_name} -f #{temp_key_path}"
          knife_reregister_out = `#{cmd}`
          Log.info "Registering new key for client #{node_name}: #{cmd}"

          unless $?.success?
            fail "Error registering client and node #{node_name}"\
                 " #{knife_reregister_out}"
          end

          # create client configuration (client.rb and validation.pem) in tmp_dir
          cmd = "knife configure client #{temp_dir}"
          template_create_out = `#{cmd}`
          Log.info "Creating new config template for client #{node_name}: #{cmd}"
          unless $?.success?
            fail "Error creating client configuration #{template_create_out}"
          end
        end

        # create bootstrap_script
        #validation_key_path = File.join(temp_dir, 'validation.pem')
        #validation_key = File.read(validation_key_path)
        validation_key = ""
        client_config_path = File.join(temp_dir, 'client.rb')
        config_content = File.read(client_config_path).gsub("'", "\"")
        config_content << "\nnode_name\t\"#{node_name}\""
        if Config.chef_server?
          config_content << "\nchef_server_url\t\"#{Config.chef_server}\""
        end

        pubkey = IO.read(pubkey_path).chomp
        first_boot = {
          sentinel_bootstrap: {
            public_key: "#{pubkey}"
          },
          run_list: [
            'recipe[sentinel_bootstrap]'
          ]
        }

        contents = File.read(template_file_path)
        bootstrap_script = Erubis::Eruby.new(contents).result(
          knife_config: {},
          chef_version: CHEF_VERSION,
          validation_key: validation_key,
          encrypted_data_bag_secret: nil,
          config_content: config_content,
          first_boot: first_boot
        )
        bootstrap_script_path = File.join(temp_dir, 'bootstrap_script')
        File.write(bootstrap_script_path, bootstrap_script)
        FileUtils.chmod(0700, bootstrap_script_path)

        # create package
        payload_dir_path = File.join(temp_dir, 'payload')
        FileUtils.mkdir_p(payload_dir_path)

        installer_path = File.join(script_dir, 'installer')
        builder_path = File.join(script_dir, 'build')
        decompress_path = File.join(script_dir, 'decompress')
        package_file_path = File.join(temp_dir, 'selfextract.bsx')

        # setup three scripts beforehand (installer, build, decompress)
        FileUtils.cp(builder_path, temp_dir)
        FileUtils.cp(decompress_path, temp_dir)
        FileUtils.cp(installer_path, payload_dir_path)
        FileUtils.cp(bootstrap_script_path, payload_dir_path)
        FileUtils.cp(temp_key_path, payload_dir_path)
        Dir.chdir(temp_dir) { `#{builder_path}` }
        Log.info "Building installer : command=#{builder_path}"

        Util.with_clean_env do
          ssh_host_name = Util.ssh_host(system)
          `ssh-keygen -R #{ssh_host_name}`
          `ssh-keyscan #{ssh_host_name} >> ~/.ssh/known_hosts`
        end

        package_file_path
      end
    end
  end
end
