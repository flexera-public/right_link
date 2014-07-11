require 'ip'
require 'ruby-wmi' if ::RightScale::Platform.windows?

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
      rename_devices
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
      major, minor, build = ::RightScale::Platform.release.split(".").map(&:to_i)
      @network_device_name = (major == 6 && minor <= 1) ? "Local Area Connection" : "Ethernet" # http://msdn.microsoft.com/en-us/library/ms724834%28VS.85%29.aspx
    end

    def os_net_devices
      @net_devices ||= (1..10).map { |i| "#{network_device_name} #{i}".sub(/ 1$/, "") }
    end

    def network_adapters
      WMI::Win32_NetworkAdapter.all
    end

    def network_devices
      @network_devices ||= network_adapters.delete_if { |dev| dev.MACAddress.nil? || dev.NetConnectionID.nil? }
                                           .sort_by { |dev| os_net_devices.index(dev.NetConnectionID) }
                                           .reverse
    end

    def device_name_from_mac(mac)
       network_devices.detect { |dev| dev.macaddress.casecmp(mac) == 0 }.NetConnectionID
    end

    def rename_device(old_name, new_name)
      old_name = shell_escape_if_necessary(old_name)
      new_name = shell_escape_if_necessary(new_name)
      runshell("netsh interface set interface #{old_name} newname=#{new_name}")
    end


    def name_from_mac(mac)
      key = ENV.select { |k,v|  k =~ /RS_IP\d_MAC/ && v == mac }.keys.first || ''
      key = key.sub('MAC', 'NAME')
      ENV[key] || os_net_devices.pop
    end

    def rename_devices_to_temp_name
      network_devices.each do |device|
        rename_device(device.NetConnectionID, safe_name(device.MACAddress))
      end
    end

    def safe_name(name)
      name.tr('<>:"/\\|?*', '.')
    end

    def rename_devices
      return if ENV.keys.grep(/RS_IP\d_NAME/).empty?
      rename_devices_to_temp_name
      ENV.keys.grep(/RS_IP\d_MAC/).each do |mac|
        n = mac[/\d/].to_i
        temp_name = safe_name(ENV[mac])
        device_name = safe_name(ENV["RS_IP#{n}_NAME"] || os_net_devices.shift)
        rename_device(temp_name, device_name)
      end
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

    def configure_network_adaptor(device, ip, netmask, gateway, nameservers = [])
      super

      cmd = "netsh interface ip set address name=#{device} source=static addr=#{ip} mask=#{netmask} gateway="
      cmd += gateway ? "#{gateway} gwmetric=1" : "none"
      runshell(cmd)
      wait_for_configuration_appliance(device, ip)

      if nameservers && nameservers.length > 0
        unless all_nameservers_match?(device, nameservers)
          nameservers.each_with_index do |n, i|
            add_nameserver_to_device(device, n, i + 1)
          end
        end
      end

      # return the IP address assigned
      ip
    end

    def add_nameserver_to_device(device, nameserver_ip, index)
      cmd = "netsh interface ipv4 add dnsserver name=#{device} addr=#{nameserver_ip} index=#{index} validate=no"
      primary = (index == 1)
      cmd = "netsh interface ipv4 set dnsserver name=#{device} source=static addr=#{nameserver_ip} register=primary validate=no" if primary
      runshell(cmd)
      true
    end

    def configured_nameservers(device)
      # show only nameservers configured staticly i.e. not through DHCP
      runshell("netsh interface ip show dns #{device}").lines.reject { |l| l =~ /DHCP/ }.join
    end

    def all_nameservers_match?(device, nameservers)
      configured = configured_nameservers(device)
      nameservers.all? { |n| configured.include?(n) }
    end

    def null_device
      "NUL"
    end
  end
end
