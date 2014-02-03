module RightScale
  class UbuntuNetworkConfigurator < CentosNetworkConfigurator
    def self.supported?
      ::RightScale::Platform.ubuntu?
    end

    def separate_configs_enabled?
      !File.readlines("/etc/network/interfaces").grep(/source \/etc\/network\/interface.d/).empty?
    end

    def enable_separate_configs
      File.open("/etc/network/interfaces", "w") do |config|
        config.write <<-EOH
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
      auto #{device}
iface #{device} inet static
address #{ip}
netmask #{netmask}
gateway #{gateway}
dns-nameservers #{nameservers.join(" ")}
      EOH
    end
  end
end
