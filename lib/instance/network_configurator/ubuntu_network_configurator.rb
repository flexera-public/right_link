module RightScale
  class UbuntuNetworkConfigurator < CentosNetworkConfigurator
    def self.supported?
      ::RightScale::Platform.linux? && ::RightScale::Platform.ubuntu?
    end

    def separate_configs_enabled?
      !File.readlines("/etc/network/interfaces").grep(/source \/etc\/network\/interface.d/).empty?
    end

    def installed_network_devices
      @installed_network_devices || = File.readlines("/proc/net/dev").grep(/eth\d+/) do |device|
        device.split(':').first.strip
      end
    end

    def staticaly_configured_network_devices
      @staticaly_configured_network_devices ||= ENV.keys.grep(/RS_IP(\d)_ADDR/) { "eth#{$1}" }
    end

    def dhcp_configure_network_devices
      installed_network_devices - staticaly_configured_network_devices
    end

    def add_static_routes_for_network
      dhcp_configure_network_devices.each { |device| runshell("dhclient #{device}") }
      super
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

    def config_data(device, ip, netmask, gateway, nameservers)
      config_data = <<-EOH
# File managed by RightScale
# DO NOT EDIT
auto #{device}
iface #{device} inet static
address #{ip}
netmask #{netmask}
EOH
      config_data << "gateway #{gateway}\n" if gateway
      config_data << "dns-nameservers #{nameservers.join(" ")}\n"
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
  end
end
