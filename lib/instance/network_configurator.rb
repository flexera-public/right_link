require 'set'
require 'fileutils'
require 'right_agent'
require File.normalize_path(File.join(File.dirname(__FILE__), 'agent_config'))

module RightScale
  class NetworkConfigurator
    class AmbiguousPlatform < Exception; end
    class UnsupportedPlatform < Exception; end

    include RightSupport::Log::Mixin

    @@subclasses = Set.new

    NETWORK_CONFIGURED_MARKER = File.join(AgentConfig.agent_state_dir, "network_configured")

    def self.inherited(klass)
      @@subclasses << klass
    end

    # Factory method to infer the correct configurator for this OS and instantiate it.
    #
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

    # Detects if configurator supported on current platform.
    # Responsibility of subclass
    #
    def self.supported?
      raise NotImplementedError, "Subclass responsibility"
    end

    # Shell escape string(puts it to quotes) if it necessary
    #
    # === Parameters
    # word(String):: string to be escaped
    #
    # == Return
    # result(String):: escaped string
    def shell_escape_if_necessary(word)
      return word if word.match(/^".*"$/) || word.match(/^\S+$/)
      word.inspect
    end

    # Detects if network was configured earlier
    #
    def already_configured?
      File.exists?(NETWORK_CONFIGURED_MARKER)
    end

    # Creates network configured marker
    #
    def set_network_configured_marker
      FileUtils.mkdir_p(File.dirname(NETWORK_CONFIGURED_MARKER))
      FileUtils.touch(NETWORK_CONFIGURED_MARKER)
    end

    # Performs network configuration. 
    #
    # === Parameters
    # network(String):: target network in CIDR notation
    def configure_network
      return if already_configured?
      add_static_ips
      # add routes for nat server
      # this needs to be done after our IPs are configured
      add_static_routes_for_network
      set_network_configured_marker
    end

    #
    # NAT Routing Support
    #

    # Add routes to external networks via local NAT server
    #
    # no-op if no RS_ROUTE<N> variables are defined
    #
    # === Return
    # result(True):: Always true
    def add_static_routes_for_network
      # required metadata values
      routes = ENV.keys.select { |k| k =~ /^RS_ROUTE(\d+)$/ }
      routes.each do |route|
        begin
          nat_server_ip, cidr = ENV[route].strip.split(/[,:]/)
          network_route_add(cidr.to_s.strip, nat_server_ip.to_s.strip)
        rescue Exception => e  
          logger.error "Detected an error while adding route to NAT #{e.class}: #{e.message}"
        end
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
        logger.debug "Route already exists to #{route_str}"
        return true
      end

      true
    end

    # Platform specific regex used to detect if a route is already defined
    #
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

    # Configures all specified network adapters with static IP addresses
    #
    def add_static_ips
      # configure static IP (if specified in metadata)
      static_ip_numerals.each do |n_ip|
        add_static_ip(n_ip)
      end
    end

    def static_ip_numerals
      static_ips = ENV.keys.select { |k| k =~ /^RS_IP\d+_ADDR$/ }
      static_ips.map { |ip_env_name| ip_env_name =~ /RS_IP(\d+)_ADDR/; $1.to_i }
    end

    # Platform specific list of default network devices names
    # Responsibility of subclasses
    #
    def os_net_devices
      raise NotImplemented
    end

    # Sets single network adapter static IP address
    #
    # Parameters
    # n_ip(Fixnum):: network adapter index
    #
    def add_static_ip(n_ip=0)
      begin
        # required metadata values
        ipaddr = ENV["RS_IP#{n_ip}_ADDR"]
        netmask = ENV["RS_IP#{n_ip}_NETMASK"]
        # optional
        gateway = ENV["RS_IP#{n_ip}_GATEWAY"]
        device = shell_escape_if_necessary(os_net_devices[n_ip])

        if ipaddr
          # configure network adaptor
          attached_nameservers = nameservers_for_device(n_ip)

          logger.info "Setting up static IP address '#{ipaddr}' for '#{device}'"
          logger.debug "Netmask: '#{netmask}' ; Gateway: '#{gateway}'"
          logger.debug "Nameservers: '#{attached_nameservers.join(' ')}'" if attached_nameservers
          raise "FATAL: RS_IP#{n_ip}_NETMASK not defined ; Cannot configure static IP address" unless netmask

          ip = configure_network_adaptor(device, ipaddr, netmask, gateway, attached_nameservers)
        end
      rescue Exception => e
        logger.error "Detected an error while configuring static IP#{n_ip}: #{e.message}"
        raise e
      end
    end


    # Configures a single network adapter with a static IP address
    #
    # Parameters
    # device(String):: device to be configured
    # ip(String):: static IP to be set
    # netmask(String):: netmask to be set
    # gateway(String):: default gateway IP to be set
    # nameservers(Array):: array of nameservers to be set
    #
    def configure_network_adaptor(device, ip, netmask, gateway, nameservers)
      raise "ERROR: invalid IP address: '#{ip}'" unless valid_ipv4?(ip)
      raise "ERROR: invalid netmask: '#{netmask}'" unless valid_ipv4?(netmask)

      # gateway is optional
      if gateway
        raise "ERROR: invalid gateway IP address: '#{gateway}'" unless valid_ipv4?(gateway)
      end
    end

    # Returns a validated list of nameservers
    #
    # == Parameters
    # none
    def nameservers_for_device(n_ip)
      nameservers = []
      raw_nameservers = ENV["RS_IP#{n_ip}_NAMESERVERS"].to_s.strip.split(/[, ]+/)
      raw_nameservers.each do |nameserver|
        if valid_ipv4?(nameserver)
          nameservers << nameserver
        else
          # Non-fatal error, we only need one working
          logger.error("Invalid nameserver #{nameserver} for interface##{n_ip}")
        end
      end
      # Also a non-fatal error, DHCP or another interface specify nameservers and we're still good
      logger.warn("No valid nameservers specified for static interface##{n_ip}") unless nameservers.length > 0
      nameservers
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

    # Platform specific name of null device to redirect output of
    # executed shell commands.
    # Responsibility of subclasses
    #
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
require File.normalize_path(File.join(NETWORK_CONFIGURATORS_DIR, 'centos_network_configurator'))
require File.normalize_path(File.join(NETWORK_CONFIGURATORS_DIR, 'ubuntu_network_configurator'))
require File.normalize_path(File.join(NETWORK_CONFIGURATORS_DIR, 'windows_network_configurator'))


