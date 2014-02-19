require 'ip'

module RightScale
  class WindowsNetworkConfigurator < NetworkConfigurator
    def self.supported?
      ::RightScale::Platform.windows?
    end

    # converts CIDR to ip/netmask
    #
    # === Parameters
    # cidr_range(String):: target range in CIDR notation
    # === Return
    # result(Array):: array which contains ip address and netmask
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

    # For Windows 2008R2/Windows 7 and earlier its Local Area Connection
    # For Windows 8/2012 and later its Ethernet
    def network_device_name
      return @network_device_name if @network_device_name
      device_out = runshell("netsh interface show interface")
      @network_device_name = device_out.include?("Local Area Connection") ? "Local Area Connection" : "Ethernet"
    end

    def os_net_devices
      @net_devices ||= (1..10).map { |i| "#{network_device_name} #{i}".sub(/ 1$/, "") }
    end

    def network_route_add(network, nat_server_ip)
      super
      network, mask = cidr_to_netmask(network)
      runshell("route -p ADD #{network} MASK #{mask} #{nat_server_ip}")
      true
    end

    # Shows network configuration for specified device
    #
    # === Parameters
    # device(String):: target device name
    #
    # === Return
    # result(String):: current config for specified device
    #
    def device_config_show(device)
      runshell("netsh interface ipv4 show addresses #{device}")
    end

    # Gets IP address for specified device
    #
    # === Parameters
    # device(String):: target device name
    #
    # === Return
    # result(String):: current IP for specified device or nil
    #
    def get_device_ip(device)
      ip_addr = device_config_show(device).lines("\n").grep(/IP Address/).shift
      return nil unless ip_addr
      ip_addr.strip.split.last
    end

    # Waits until device configuration applies i.e.
    # until device IP == specified IP
    #
    def wait_for_configuration_appliance(device, ip)
      sleep(2) while ip != get_device_ip(device)
    end

    def configure_network_adaptor(device, ip, netmask, gateway, nameservers)
      super

      cmd = "netsh interface ip set address name=#{device} source=static addr=#{ip} mask=#{netmask} gateway="
      cmd += gateway ? "#{gateway} gwmetric=1" : "none"
      runshell(cmd)
      wait_for_configuration_appliance(device, ip)

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
