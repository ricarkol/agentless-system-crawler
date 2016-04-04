# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2015 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
module SentinelDocker
  module Bootstrap
    module Windows
      def self.command(system, user, pass, chef_server, pubkey)
        "knife bootstrap windows winrm #{system.ip} -x '#{user}'"\
        " -P $#{pass} -p 5985 -r 'recipe[windows_bootstrap_cookbook]'"\
        " -N #{system.node_name} --bootstrap-version #{CHEF_VERSION}"\
        " --distro chef-windows-sentinel"
      end

      def self.disavow_command
        'rd /S /Q "C:\chef_sentinel"'
      end

      def self.run_command(system, mode, parameters, recipes)
        tmpfilename = "%TEMP%\\sentinel.chef.#{SecureRandom.hex}"

        cmd =
          "ssh -o StrictHostKeyChecking=no"\
          " -i #{Config.ssh_key} -p #{system.port}"\
          " #{system.user}@#{system.ip} \""

        cmd += %{> #{tmpfilename} ( echo.#{parameters.to_json} ) & }
        cmd += "chef-client"
        args =
          "-c C:\\chef_sentinel\\client.rb #{mode == :check ? '-W' : ''}"\
          " -j #{tmpfilename} -o '#{recipes}' --no-color\""

        [cmd, args]
      end

      def self.installer(system, temp_dir)
        raise "Not implemented"
      end
    end
  end
end
