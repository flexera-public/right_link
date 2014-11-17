require 'ip'

module RightScale
  class CentosNetworkConfigurator < NetworkConfigurator
    def self.supported?
      ::RightScale::Platform.linux? && (::RightScale::Platform.centos? || ::RightScale::Platform.rhel?)
    end

    def single_ip_range?(cidr_range)
      range = IP::CIDR.new(cidr_range)
      range.first_ip == range.last_ip
    end

    def os_net_device_config(device)
      config_data = runshell("ip addr show #{device}")
      config = {}
      if match_data = /inet ([\d\.]+)\/(\d+) /.match(config_data)
        config["ip"] = match_data[1]
        config["mask_length"] = match_data[2]
        cidr = IP::CIDR.new("#{match_data[1]}/#{match_data[2]}")
        config["netmask"] = cidr.long_netmask.ip_address
        config["name"] = device
      end
      if match_data = /link\/\w+ ([^ ]+) /.match(config_data)
        config["mac"] = match_data[1]
      end
      if config_data =~ /state UP/
        config["up"] = true
      end
      config
    end

    def route_device(network, nat_server_ip)
      device = nil
      # Have to associate it with the correct static
      static_ip_numerals.each do |n_ip|
        ip = ENV["RS_IP#{n_ip}_ADDR"]
        netmask = ENV["RS_IP#{n_ip}_NETMASK"]
        static_device = shell_escape_if_necessary(device_name_from_mac(ENV["RS_IP#{n_ip}_MAC"]))
        if IPAddr.new(ip).mask(netmask).include?(nat_server_ip)
          device = static_device
          break
        end
      end

      # Not a statically configured device, DHCP - check system, but only
      # in the post-networking step, after DHCP has been set up
      if ! @boot && ! device
        os_net_devices.each do |net_device|
          device_config = os_net_device_config(net_device)
          if device_config["ip"] && device_config["netmask"]
            if IPAddr.new(device_config["ip"]).mask(device_config["netmask"]).include?(nat_server_ip)
              device = net_device
            end
          end
        end
      end

      device 
    end

    # This is now quite tricky. We do two routing passes, a pass before the
    # system networking is setup (@boot is true) in which we setup static system
    # config files and a pass after system networking (@boot is false) in which 
    # we fix up the remaining routes cases involving DHCP. We have to set any routes 
    # involving DHCP post networking as we can't know the DHCP gateway beforehand
    def network_route_add(network, nat_server_ip)
      super

      route_str = "#{network} via #{nat_server_ip}"
      begin
        if @boot
          logger.info "Adding route to network #{route_str}"
          device = route_device(network, nat_server_ip)
          if device
            update_route_file(network, nat_server_ip, device)
          else
            logger.warn "Unable to find associated device for #{route_str} in pre-networking section. As network devices aren't setup yet, will try again after network start."
          end
        else
          if network_route_exists?(network, nat_server_ip)
            logger.debug "Route already exists to #{route_str}"
          else
            logger.info "Adding route to network #{route_str}"
            runshell("ip route add #{route_str}")
            device = route_device(network, nat_server_ip)
            if device
              update_route_file(network, nat_server_ip, device)
            else
              logger.error "Unable to set route in system config: unable to find associated device for #{route_str} post-networking."
              # No need to raise here -- ip route should have failed above if there is no device to attach to
            end
          end
        end
      rescue Exception => e
        logger.error "Unable to set a route #{route_str}. Check network settings."
        # XXX: for some reason network_route_exists? allowing mutple routes
        # to be set.  For now, don't fail if route already exists.
        throw e unless e.message.include?("NETLINK answers: File exists")
      end
      true
    end

    def route_regex(network, nat_server_ip)
      unless network == "default"
        network = network.split("/").first if single_ip_range?(network)
      end
      /#{network}.*via.*#{nat_server_ip}/
    end

    def routes_show
      runshell("ip route show")
    end

    def os_net_devices
      unless @net_devices
        @net_devices =
          runshell("ip link show").split("\n").
          select {|line| line =~ /^\d/}.
          map {|line| line.split[1].sub(":","")}.
          select {|device| device =~ /^eth/}
      end
      @net_devices
    end

    def device_name_from_mac(mac)
      `grep -i -l '#{mac}' /sys/class/net/*/address | cut -d / -f 5`.strip
    end

    def routes_file(device)
      "/etc/sysconfig/network-scripts/route-#{device}"
    end

    def ip_route_cmd(network, nat_server_ip)
      "#{network} via #{nat_server_ip}"
    end

    # Persist network route to file
    #
    # If the file does not exist, it will be created.
    # If the route already exists, it will not be added again.
    #
    # === Parameters
    # network(String):: target network in CIDR notation
    # nat_server_ip(String):: the IP address of the NAT "router"
    #
    # === Return
    # result(True):: Always returns true
    def update_route_file(network, nat_server_ip, device)
      raise "ERROR: invalid nat_server_ip : '#{nat_server_ip}'" unless valid_ipv4?(nat_server_ip)
      raise "ERROR: invalid CIDR network : '#{network}'" unless valid_ipv4_cidr?(network)

      routes_file = routes_file(device)
      ip_route_cmd = ip_route_cmd(network, nat_server_ip)

      update_config_file(
        routes_file,
        ip_route_cmd,
        "Route to #{ip_route_cmd} already exists in #{routes_file}",
        "Appending #{ip_route_cmd} route to #{routes_file}"
      )
      true
    end


    def default_gateway
      @default_gateway ||= runshell("ip -4 route list 0/0").split(" ")[2] rescue nil
    end

    def delete_gateway_route(gateway)
      begin
        runshell("route del default gw #{gateway}")
      rescue Exception => e
        logger.error "Unable to delete a route to gateway at #{gateway}."
      end
    end

    def metadata_gateway
      @metadata_gateway ||= ENV.select { |key, value| key =~ /RS_IP\d_GATEWAY/ }.values.first
    end

    def set_default_gateway
      unless metadata_gateway.nil? || metadata_gateway == default_gateway
        delete_gateway_route(default_gateway) if default_gateway
        add_gateway_route(metadata_gateway)
      end
    end

    def configure_routes
      super
      set_default_gateway unless @boot
    end

    # Add default gateway route
    #
    # === Parameters
    # gateway(String):: IP address of gateway
    #
    def add_gateway_route(gateway)
      begin
        # this will throw an exception, if the gateway IP is unreachable.
        runshell("route add default gw #{gateway}") unless network_route_exists?("default", gateway)
      rescue Exception => e
        logger.error "Unable to set a route to gateway at #{gateway}. Check your RS_IP0_GATEWAY value"
      end
    end

    def add_dhcp_adapters
      dhcp_ip_assigment_numerals.each do |n_assigment|
        device = "eth#{n_assigment}"
        config_file = config_file(device)
        logger.info("Configuring #{device} for DHCP")
        write_adaptor_config(device, config_data_dhcp(device)) unless File.exists?(config_file)
      end
    end

    # Persist device config to a file
    #
    # If the file does not exist, it will be created.
    #
    # === Parameters
    # device(String):: target device name
    # data(String):: target device config
    #
    def write_adaptor_config(device, data)
      config_file = config_file(device)
      raise "FATAL: invalid device name of '#{device}' specified for static IP allocation" unless device.match(/eth[0-9+]/)
      logger.info "Writing persistent network configuration to #{config_file}"
      File.open(config_file, "w") { |f| f.write(data) }
    end

    def config_file(device)
      FileUtils.mkdir_p("/etc/sysconfig/network-scripts")
      "/etc/sysconfig/network-scripts/ifcfg-#{device}"
    end

    def config_data_dhcp(device)
<<-EOH
# File managed by RightScale
# DO NOT EDIT
DEVICE=#{device}
BOOTPROTO=dhcp
ONBOOT=yes
EOH
    end

    def config_data(device, ip, netmask, gateway, nameservers = [])

      config_data = <<-EOH
# File managed by RightScale
# DO NOT EDIT
DEVICE=#{device}
BOOTPROTO=none
ONBOOT=yes
GATEWAY=#{gateway}
NETMASK=#{netmask}
IPADDR=#{ip}
USERCTL=no
PEERDNS=yes
EOH
      if nameservers && nameservers.length > 0
        nameservers.each_with_index do |n, i|
          config_data << "DNS#{i+1}=#{n}\n"
        end
      end
      config_data
    end

    # NOTE: not idempotent -- it will always all ifconfig and write config file
    def configure_network_adaptor(device, ip, netmask, gateway, nameservers)
      super

      # Setup static IP without restarting network
      unless @boot
        logger.info "Updating in memory network configuration for #{device}"
        runshell("ifconfig #{device} #{ip} netmask #{netmask}")
        add_gateway_route(gateway) if gateway
      end

      # Also write to config file
      write_adaptor_config(device, config_data(device, ip, netmask, gateway, nameservers))

      # return the IP address assigned
      ip
    end


    # Add line to config file
    #
    # If the file does not exist, it will be created.
    # If the line already exists, it will not be added again.
    #
    # === Parameters
    # filename(String):: absolute path to config file
    # line(String):: line to add
    #
    # === Return
    # result(Hash):: Hash-like leaf value
    def update_config_file(filename, line, exists_str=nil, append_str=nil)

      FileUtils.mkdir_p(File.dirname(filename)) # make sure the directory exists

      if read_config_file(filename).include?(line)
        exists_str ||= "Config already exists in #{filename}"
        logger.info exists_str
      else
        append_str ||= "Appending config to #{filename}"
        logger.info append_str
        append_config_file(filename, line)
      end
      true
    end

    # Read contents of config file
    #
    # If file doesn't exist, return empty string
    #
    # === Return
    # result(String):: All lines in file
    def read_config_file(filename)
      contents = ""
      File.open(filename, "r") { |f| contents = f.read() } if File.exists?(filename)
      contents
    end

    # Appends line to config file
    #
    def append_config_file(filename, line)
      File.open(filename, "a") { |f| f.puts(line) }
    end

    def null_device
      "/dev/null"
    end
  end
end
