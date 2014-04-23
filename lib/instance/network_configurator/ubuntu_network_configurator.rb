module RightScale
  class UbuntuNetworkConfigurator < CentosNetworkConfigurator
    def self.supported?
      ::RightScale::Platform.linux? && ::RightScale::Platform.ubuntu?
    end

    def separate_configs_enabled?
      !File.readlines("/etc/network/interfaces").grep(/source \/etc\/network\/interface.d/).empty?
    end

    def enable_separate_configs
      File.open("/etc/network/interfaces", "w") do |config|
        config.write <<-EOH
# File managed by RightScale
# DO NOT EDIT
auto lo
iface lo inet loopback

source /etc/network/interfaces.d/*.cfg
        EOH
      end
    end

    def config_file(device)
      enable_separate_configs unless separate_configs_enabled?
      FileUtils.mkdir_p("/etc/network/interfaces.d/")
      "/etc/network/interfaces.d/#{device}.cfg"
    end

    def config_data(device, ip, netmask, gateway, nameservers = [])
      config_data = <<-EOH
# File managed by RightScale
# DO NOT EDIT
auto #{device}
iface #{device} inet static
address #{ip}
netmask #{netmask}
EOH
      config_data << "gateway #{gateway}\n" if gateway
      if nameservers && nameservers.length > 0
        config_data << "dns-nameservers #{nameservers.join(" ")}\n"
      end
    end

    def ip_route_cmd(network, nat_server_ip)
      "up ip route add #{network} via #{nat_server_ip}"
    end

    def init_device_config_file(file_path, device)
      File.open(file_path, "w") do |config|
        config.write <<-EOH
# File managed by RightScale
# DO NOT EDIT
auto #{device}
iface #{device} inet dhcp
        EOH
      end
    end

    def routes_file(device)
      routes_file = config_file(device)
      init_device_config_file(routes_file, device) unless File.exists?(routes_file)
      routes_file
    end

    def restart_network
      # Until startup scripts are rewritten with Upstart, networking will start
      # ahead of the network configurator and start dhclient, so be sure to kill
      # it or it'll reconfigure the network.  
      runshell("pkill dhclient3 || true")
      devices = runshell("ifquery --list").chomp.split("\n")
      devices.select! { |d| d.include?("eth") }
      # On ubuntu, networking restart scripts
      # use ifdown and ifup, which are fairly fragile. If any parameter changes out
      # from under them (such as we're doing now with static networking config)
      # they won't fully run -- dns-nameservers scripts will be ignored. Pass a
      # --force to ignore these issues.
      devices.each { |d| runshell("ifdown #{d} --force || true") }
      runshell("/etc/init.d/networking start")
    end
  end
end
