#
# Copyright (c) 2011 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

VSCALE_DEFINITION_VERSION = 0.2

CONFIG_DRIVE_MOUNTPOINT = "/mnt/metadata" unless ::RightScale::Platform.windows?
CONFIG_DRIVE_MOUNTPOINT = "a:\\" if ::RightScale::Platform.windows?

# dependencies.
metadata_source 'metadata_sources/file_metadata_source'
metadata_writers 'metadata_writers/dictionary_metadata_writer',
                 'metadata_writers/ruby_metadata_writer',
                 'metadata_writers/shell_metadata_writer'

# set abbreviation for non-RS env var generation
abbreviation :vs

# converts CIDR to ip/netmask
#
def cidr_to_netmask(cidr_range)
  cidr = IP::CIDR.new(cidr_range)
  return cidr.ip.ip_address, cidr.long_netmask.ip_address
end



# Parses vsoup user metadata into a hash.
#
# === Parameters
# tree_climber(MetadataTreeClimber):: tree climber
# data(String):: raw data
#
# === Return
# result(Hash):: Hash-like leaf value
def create_user_metadata_leaf(tree_climber, data)
  result = tree_climber.create_branch
  ::RightScale::CloudUtilities.split_metadata(data.strip, "\n", result)
  result
end

def cloud_metadata_is_flat(clazz, path, query_result)
  false
end

# userdata defaults
default_option([:metadata_source, :user_metadata_source_file_path], File.join(CONFIG_DRIVE_MOUNTPOINT, 'user.txt'))
default_option([:user_metadata, :metadata_tree_climber, :create_leaf_override], method(:create_user_metadata_leaf))

# cloud metadata defaults
default_option([:metadata_source, :cloud_metadata_source_file_path], File.join(CONFIG_DRIVE_MOUNTPOINT, 'meta.txt'))
default_option([:cloud_metadata, :metadata_tree_climber, :create_leaf_override], method(:create_user_metadata_leaf))
# vscale cloud_metadata is flat, so paths will never have children -- always return false
default_option([:cloud_metadata, :metadata_tree_climber, :has_children_override], method(:cloud_metadata_is_flat))


# Determines if the current instance is running on vsoup.
#
# === Return
# true if running on rackspace
def is_current_cloud?
  return true
end

def write_cloud_metadata
  result = write_metadata(:cloud_metadata)
  # TODO: this is a dirty hack for Windows to avoid recompiling service DLL for
  #       vScale PoC network config features.  This functionality will be moved to
  #       system_configurator at some point and should then be removed
  configure_network if platform.windows?
  result
end

def shell_escape_if_necessary(word)
  return word if word.match(/^".*"$/) || word.match(/^\S+$/)
  word.inspect
end

def configure_network
  load_metadata

  # configure static IP (if specified in metadata)
  device = ENV['RS_STATIC_IP0_DEVICE']
  device ||= platform.windows? ? "Local Area Connection" : "eth0"
  static_ip = add_static_ip(shell_escape_if_necessary(device))
  if platform.windows?
    # setting administrator password setting (not yet supported)
  else
    # update authorized_keys file from metadata
    public_key = get_public_ssh_key_from_metadata()
    update_authorized_keys(public_key)
  end
  # add routes for nat server
  # this needs to be done after our IPs are configured
  add_static_routes_for_network
end

# Updates the given node with cloud metadata details.
#
# We also do a bunch of VM configuration here.
# There is likely a better place we can do all this.
#
# === Return
# always true
def update_details
  details = {}
  details[:public_ips] = Array.new
  details[:private_ips] = Array.new

  load_metadata
  configure_network

  if platform.windows?
    # report new network interface configuration to ohai
    if ohai = @options[:ohai_node]
      details[:public_ipv4] = ::RightScale::CloudUtilities.ip_for_windows_interface(ohai, 'Local Area Connection')
      details[:local_ipv4] = ::RightScale::CloudUtilities.ip_for_windows_interface(ohai, 'Local Area Connection 2')
    end
  else
    # report new network interface configuration to ohai
    if ohai = @options[:ohai_node]
      # Pick up all IPs detected by ohai
      n = 0
      while (ip = ::RightScale::CloudUtilities.ip_for_interface(ohai, "eth#{n}")) != nil
        type = "public_ip"
        type = "private_ip" if is_private_ipv4(ip)
        details[type.to_sym] ||= ip      # store only the first found for type
        details["#{type}s".to_sym] << ip # but append all to the list
        n += 1
      end
    end
  end

  # Override with statically assigned IP (if specified)
  static_ip = ENV['RS_STATIC_IP0_ADDR']
  if static_ip
    if is_private_ipv4(static_ip)
      details[:private_ip] ||= static_ip
      details[:private_ips] << static_ip
    else
      details[:public_ip] ||= static_ip
      details[:public_ips] << static_ip
    end
  end

  details
end

#
# Methods for update details
#

# Loads metadata from file into environment
#
def load_metadata
  begin
    load(::File.join(RightScale::AgentConfig.cloud_state_dir, 'meta-data.rb'))
  rescue Exception => e
    raise "FATAL: Cannot load metadata from #{meta_data_file}"
  end
end

#
# Authorized SSH Key for root (linux only)
#

# Gets public key string from cloud metadata file
#
# === Return
# public_key(String):: A public SSH key
def get_public_ssh_key_from_metadata
  public_key = ENV['VS_SSH_PUBLIC_KEY']
  # was there a key found?
  if public_key.nil? || public_key.empty?
    logger.warn "No public SSH key found in metadata"
    return
  end
  public_key
end

# Add public key to ssh authorized_keys file
#
# If the file does not exist, it will be created.
# If the key already exists, it will not be added again.
#
# === Parameters
# public_key(String):: public ssh key
#
# === Return
# result(Hash):: Hash-like leaf value
def update_authorized_keys(public_key)
  auth_key_file = "/root/.ssh/authorized_keys"

  if public_key.nil? || public_key.empty?
    logger.warn "No public SSH key specified -- no modifications to #{auth_key_file} made"
    return
  end

  update_config_file(
    auth_key_file,
    public_key,
    "Public ssh key for root already exists in #{auth_key_file}",
    "Appending public ssh key to #{auth_key_file}"
  )

  # make sure it's private
  FileUtils.chmod(0600, auth_key_file)
  true
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
        update_route_file(network, nat_server) unless platform.windows?
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

  if platform.windows?
    network, mask = cidr_to_netmask(network)
    runshell("route -p ADD #{network} MASK #{mask} #{nat_server_ip}")
  else
    logger.info "Adding route to network #{route_str}"
    begin
      runshell("ip route add #{route_str}")
    rescue Exception => e
      logger.error "Unable to set a route #{route_str}. Check network settings."
      # XXX: for some reason network_route_exists? allowing mutple routes
      # to be set.  For now, don't fail if route already exists.
      throw e unless e.message.include?("NETLINK answers: File exists")
    end
  end
  true
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
def update_route_file(network, nat_server_ip, device = "eth0")
  raise "ERROR: invalid nat_server_ip : '#{nat_server_ip}'" unless valid_ipv4?(nat_server_ip)
  raise "ERROR: invalid CIDR network : '#{network}'" unless valid_ipv4_cidr?(network)

  # We leave out the "dev eth0" from the end of the ip_route_cmd here.
  # This allows for the route to go through a different interface,
  # which is good for instances that have multiple interfaces.
  # This is a little weird in the case where the route is brought up
  # with eth0 but possibly applies to eth1
  # Probably should figure out which device has the subnet that nat_server_ip is on
  ip_route_cmd = "#{network} via #{nat_server_ip}"
  routes_file = "/etc/sysconfig/network-scripts/route-#{device}"

  update_config_file(
    routes_file,
    ip_route_cmd,
    "Route to #{ip_route_cmd} already exists in #{routes_file}",
    "Appending #{ip_route_cmd} route to #{routes_file}"
  )
  true
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
  route_regex = if platform.windows?
                  network, mask = cidr_to_netmask(network)
                  /#{network}.*#{mask}.*#{nat_server_ip}/
                else
                  /#{network}.*via.*#{nat_server_ip}/
                end
  matchdata = routes.match(route_regex)
  matchdata != nil
end

# Get the currently defined routing table
#
# === Return
# result(String):: results from route query
def routes_show
  runshell(platform.windows? ? "route print" : "ip route show")
end

#
# Static IP Support
#

# Configures a single network adapter with a static IP address
#
# no-op if 'RS_STATIC_IP0_ADDR' is not defined in metadata
#
# === Return
# result(String):: the static ip address assigned. nil if nothing assigned
def add_static_ip(device)
  ip = nil
  begin
    # required metadata values
    ipaddr = ENV['RS_STATIC_IP0_ADDR']
    netmask = ENV['RS_STATIC_IP0_NETMASK']
    # optional
    nameservers_string = ENV['RS_STATIC_IP0_NAMESERVERS']
    gateway = ENV['RS_STATIC_IP0_GATEWAY']

    if ipaddr
      logger.info "Setting up static IP address #{ipaddr} for #{device}"
      logger.debug "Netmask: '#{netmask}' ; gateway: '#{gateway}' ; nameservers: '#{nameservers_string.inspect}'"
      raise "FATAL: RS_STATIC_IP0_NETMASK not defined ; Cannot configure static IP address" unless netmask
      raise "FATAL: RS_STATIC_IP0_NAMESERVERS not defined ; Cannot configure static IP address" unless nameservers_string
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

  ip
end

# NOTE: not idempotent -- it will always all ifconfig and write config file
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

  if platform.windows?
    cmd = "netsh interface ip set address name=#{device} source=static addr=#{ip} mask=#{netmask} gateway="
    cmd += gateway ? "#{gateway} gwmetric=1" : "none"
    runshell(cmd)
  else
    # Setup static IP without restarting network
    logger.info "Updating in memory network configuration for #{device}"
    runshell("ifconfig #{device} #{ip} netmask #{netmask}")
    add_gateway_route(gateway) if gateway

    # Also write to config file
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
DNS1=#{nameservers[0]}
DNS2=#{nameservers[1]}
PEERDNS=yes
EOH
write_adaptor_config(device, config_data)
  end

  # return the IP address assigned
  ip
end

def add_gateway_route(gateway)
  begin
    # this will throw an exception, if the gateway IP is unreachable.
    runshell("route add default gw #{gateway}") unless network_route_exists?("default", gateway)
  rescue Exception => e
    logger.error "Unable to set a route to gateway at #{gateway}. Check your RS_STATIC_IP0_GATEWAY value"
  end
end

def write_adaptor_config(device, data)
  raise "FATAL: invalid device name of '#{device}' specified for static IP allocation" unless device.match(/eth[0-9+]/)
  FileUtils.mkdir_p("/etc/sysconfig/network-scripts")
  config_file = "/etc/sysconfig/network-scripts/ifcfg-#{device}" # TODO: centos specific
  logger.info "Writing persistent network configuration to #{config_file}"
  File.open(config_file, "w") { |f| f.write(data) }
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

  if platform.windows?
    runshell("netsh interface ip add dns #{device} #{nameserver_ip} index=#{index}")
  else
    config_file="/etc/resolv.conf"
    logger.info "Added nameserver #{nameserver_ip} to #{config_file}"
    File.open(config_file, "a") {|f| f.write("nameserver #{nameserver_ip}\n") }
  end
  true
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
  contents = ""
  if platform.windows?
    contents = runshell("netsh interface ip show dns #{device}")
  else
  begin
    File.open("/etc/resolv.conf", "r") { |f| contents = f.read() }
  rescue
    logger.warn "Unable to open /etc/resolv.conf. It will be created"
  end
  end
  contents
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

# We return two lists of public IPs respectively private IPs to the GW. The is_private_ip
# test is used to sort the IPs of an instance into these lists. Not perfect but
# customizable.
#
# === Parameters
# ip(String):: an IPv4 address
#
# === Return
# result(Boolean):: true if format is okay, else false
def is_private_ipv4(ip)
 regexp = /\A(10\.|192\.168\.|172\.1[6789]\.|172\.2.\.|172\.3[01]\.)/
 ip =~ regexp
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

# Run a Linux system command
#
# === Raise
# StandardError:: if command fails
#
# === Return
# result(String):: output from the command
def runshell(command)
  logger.info "+ #{command}"
  output = `#{command} < #{platform.windows? ? "NUL" : "/dev/null"} 2>&1`
  raise StandardError, "Command failure: #{output}" unless $?.success?
  output
end
