require 'ip'

module RightScale
  class WindowsNetworkConfigurator < NetworkConfigurator
    def self.supported?
      ::RightScale::Platform.windows?
    end

    # converts CIDR to ip/netmask
    #
    def cidr_to_netmask(cidr_range)
      cidr = IP::CIDR.new(cidr_range)
      return cidr.ip.ip_address, cidr.long_netmask.ip_address
    end

    def configure_network
      super
      # setting administrator password setting (not yet supported)
    end

    def route_regex(network, nat_server_ip)
      network, mask = cidr_to_netmask(network)
      /#{network}.*#{mask}.*#{nat_server_ip}/
    end

    def routes_show
      runshell("route print")
    end

    def os_net_devices
      @net_devices ||= (1..10).map { |i| "Local Area Connection #{i}".sub(/ 1$/, "") }
    end

    def network_route_add(network, nat_server_ip)
      super
      network, mask = cidr_to_netmask(network)
      runshell("route -p ADD #{network} MASK #{mask} #{nat_server_ip}")
      true
    end
    def configure_network_adaptor(device, ip, netmask, gateway, nameservers)
      super

      cmd = "netsh interface ip set address name=#{device} source=static addr=#{ip} mask=#{netmask} gateway="
      cmd += gateway ? "#{gateway} gwmetric=1" : "none"
      runshell(cmd)

      # return the IP address assigned
      ip
    end

    def internal_nameserver_add(nameserver_ip, index=nil,device=nil)
      cmd = "netsh interface ipv4 add dnsserver name=#{device} addr=#{nameserver_ip} index=#{index} validate=no"
      primary = (index == 1)
      cmd = "netsh interface ipv4 set dnsserver name=#{device} source=static addr=#{nameserver_ip} register=primary validate=no" if primary
      runshell(cmd)
      true
    end

    def namservers_show(device=nil)
      runshell("netsh interface ip show dns #{device}")
    end

    def null_device
      "NUL"
    end
  end
end
