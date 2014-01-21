require 'set'

module RightScale
  class NetworkConfigurator
    class AmbiguousPlatform < Exception; end
    class UnsupportedPlatform < Exception; end

    include RightSupport::Log::Mixin

    @@subclasses = Set.new

    def self.inherited(klass)
      @@subclasses << klass
    end

    # Factory method to infer the correct configurator for this OS and instantiate it.
    def self.create(*args)
      supported = @@subclasses.select { |sc| sc.supported? }

      case supported.size
      when 1
        supported.first.new(*args)
      when 0
        raise UnsupportedPlatform, "no supported configurator found"
      else
        raise AmbiguousPlatform, "Multiple configurators #{supported.inspect} are supported?!"
      end
    end

    def self.supported?
      raise NotImplementedError, "Subclass responsibility"
    end



    def shell_escape_if_necessary(word)
      return word if word.match(/^".*"$/) || word.match(/^\S+$/)
      word.inspect
    end

    def configure_network
      add_static_ips
      # add routes for nat server
      # this needs to be done after our IPs are configured
      add_static_routes_for_network
    end

    #
    # NAT Routing Support
    #

    # Add routes to external networks via local NAT server
    #
    # no-op if 'RS_NAT_ADDRESS' is not defined in metadata
    #
    # === Return
    # result(True):: Always true
    def add_static_routes_for_network
      begin
        # required metadata values
        nat_server = ENV['RS_NAT_ADDRESS']
        if nat_server
          parse_array(ENV['RS_NAT_RANGES']).each do |network|
            network_route_add(network, nat_server)
          end
        end
      rescue Exception => e
        logger.error "Detected an error while adding routes to NAT"
        raise e
      end
      true
    end

    # Add route to network through NAT server
    #
    # Will not add if route already exists
    #
    # === Parameters
    # network(String):: target network in CIDR notation
    # nat_server_ip(String):: the IP address of the NAT "router"
    #
    # === Raise
    # StandardError:: Route command fails
    #
    # === Return
    # result(True):: Always returns true
    def network_route_add(network, nat_server_ip)
      raise "ERROR: invalid nat_server_ip : '#{nat_server_ip}'" unless valid_ipv4?(nat_server_ip)
      raise "ERROR: invalid CIDR network : '#{network}'" unless valid_ipv4_cidr?(network)
      route_str = "#{network} via #{nat_server_ip}"
      if network_route_exists?(network, nat_server_ip)
        logger.info "Route already exists to #{route_str}"
        return true
      end

      true
    end

    def route_regex(network, nat_server_ip)
      raise NotImplemented
    end

    # Is a route defined to network via NAT "router"?
    #
    # === Parameters
    # network(String):: target network in CIDR notation
    # nat_server_ip(String):: the IP address of the NAT "router"
    #
    # === Return
    # result(Boolean):: true if route exists, else false
    def network_route_exists?(network, nat_server_ip)
      routes = routes_show()
      matchdata = routes.match(route_regex(network, nat_server_ip))
      matchdata != nil
    end

    # Get the currently defined routing table
    #
    # === Return
    # result(String):: results from route query
    def routes_show
      raise NotImplemented
    end

    #
    # Static IP Support
    #

    def add_static_ips
      # configure static IP (if specified in metadata)
      static_ips = ENV.collect { |k, _| k if k =~ /RS_STATIC_IP\d_ADDR/ }.compact
      static_ips.map { |ip_env_name| ip_env_name =~ /RS_STATIC_IP(\d)_ADDR/; $1.to_i }.each do |n_ip|
        add_static_ip(n_ip)
      end
    end

    def os_net_devices
      raise NotImplemented
    end

    # Configures a single network adapter with a static IP address
    #
    def add_static_ip(n_ip=0)
      # required metadata values
      ipaddr = ENV["RS_STATIC_IP#{n_ip}_ADDR"]
      netmask = ENV["RS_STATIC_IP#{n_ip}_NETMASK"]
      # optional
      nameservers_string = ENV["RS_STATIC_IP#{n_ip}_NAMESERVERS"]
      gateway = ENV["RS_STATIC_IP#{n_ip}_GATEWAY"]
      device = shell_escape_if_necessary(os_net_devices[n_ip])

      if ipaddr
        logger.info "Setting up static IP address #{ipaddr} for #{device}"
        logger.debug "Netmask: '#{netmask}' ; gateway: '#{gateway}' ; nameservers: '#{nameservers_string.inspect}'"
        raise "FATAL: RS_STATIC_IP#{n_ip}_NETMASK not defined ; Cannot configure static IP address" unless netmask
        raise "FATAL: RS_STATIC_IP#{n_ip}_NAMESERVERS not defined ; Cannot configure static IP address" unless nameservers_string
        # configure DNS
        nameservers = parse_array(nameservers_string)
        nameservers.each_with_index do |nameserver, index|
          nameserver_add(nameserver, index + 1, device)
        end
        # configure network adaptor
        ip = configure_network_adaptor(device, ipaddr, netmask, gateway, nameservers)
      end
    rescue Exception => e
      logger.error "Detected an error while configuring static IP"
      raise e
    end

    def configure_network_adaptor(device, ip, netmask, gateway, nameservers)
      raise "ERROR: 'nameserver' parameter must be an array" unless nameservers.is_a?(Array)
      raise "ERROR: invalid IP address: '#{nameserver}'" unless valid_ipv4?(ip)
      raise "ERROR: invalid netmask: '#{netmask}'" unless valid_ipv4?(netmask)
      nameservers.each do |nameserver|
        raise "ERROR: invalid nameserver: '#{nameserver}'" unless valid_ipv4?(nameserver)
      end

      # gateway is optional
      if gateway
        raise "ERROR: invalid gateway IP address: '#{gateway}'" unless valid_ipv4?(gateway)
      end
    end


    # Add nameserver to DNS entries
    #
    # Will not add if it already exists
    #
    # === Parameters
    # nameserver_ip(String):: the IP address of the nameserver
    #
    # === Raise
    # StandardError:: if unable to add nameserver
    #
    # === Return
    # result(True):: Always returns true
    def nameserver_add(nameserver_ip, index=nil,device=nil)
      raise "ERROR: invalid nameserver IP address of #{nameserver}" unless valid_ipv4?(nameserver_ip)
      if nameserver_exists?(nameserver_ip, device)
        logger.info "Nameserver #{nameserver_ip} already exists"
        return true
      end
      internal_nameserver_add(nameserver_ip, index, device)
    end


    def internal_nameserver_add(nameserver_ip, index=nil, device=nil)
      raise NotImplemented
    end

    # Is nameserver already configured?
    #
    # === Parameters
    # nameserver_ip(String):: the IP address of the nameserver
    #
    # === Return
    # result(Boolean):: true if route exists, else false
    def nameserver_exists?(nameserver_ip, device=nil)
      nameservers = namservers_show(device)
      matchdata = nameservers.match(/#{nameserver_ip}/)
      matchdata != nil
    end

    # Get the currently defined nameserver configuration
    #
    # === Return
    # result(String):: results from nameserver query
    def namservers_show(device=nil)
      raise NotImplemented
    end

    # Parse comma-delimited string into an array
    #
    # removes any quotes and leading/trailing whitespace
    #
    # === Return
    # result(Array):: Array of things
    def parse_array(comma_separated_string)
      comma_separated_string.split(',').map { |item| item.gsub(/\\\"/,""); item.strip }
    end

    # Verifies the format of an IPv4 address
    #
    # === Return
    # result(Boolean):: true if format is okay, else false
    def valid_ipv4?(ipv4_address)
      ipv4_address =~ /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/
    end

    # Verifies the format of an IPv4 cider address
    #
    # === Return
    # result(Boolean):: true if format is okay, else false
    def valid_ipv4_cidr?(ipv4_address)
      ipv4_address =~ /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\/[0-9]{1,2}$/
    end

    def null_device
      raise NotImplemented
    end


    # Run a system command
    #
    # === Raise
    # StandardError:: if command fails
    #
    # === Return
    # result(String):: output from the command
    def runshell(command)
      logger.info "+ #{command}"
      output = `#{command} < #{null_device} 2>&1`
      raise StandardError, "Command failure: #{output}" unless $?.success?
      output
    end
  end
end

NETWORK_CONFIGURATORS_DIR = File.join(File.dirname(__FILE__), 'network_configurator')
require File.normalize_path(File.join(NETWORK_CONFIGURATORS_DIR, 'linux_network_configurator'))
require File.normalize_path(File.join(NETWORK_CONFIGURATORS_DIR, 'windows_network_configurator'))


