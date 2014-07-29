#
# Copyright (c) 2010-2014 RightScale Inc
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
#

require 'net/http'
require 'uri'
require 'rexml/document'

module ::Ohai::Mixin::ShouldBeRenamed

  # def dhcp_server
  #   dhcp_server = if /cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM
  #     `ipconfig /all`.match(/DHCP Server.*: (\d+\.\d+\.\d+\.\d+)$/)[1]
  #   else
  #     # ubuntu 12 location, need to search all locs for other OSes
  #     File.read("/var/lib/dhcp/dhclient.eth0.leases").match(/dhcp-server-identifier (.*);/)[1]
  #   end
  #   dhcp_server
  # end

  # Searches for a file containing dhcp lease information.
  def dhcp_lease_provider
    if RUBY_PLATFORM =~ /windows|cygwin|mswin|mingw|bccwin|wince|emx/
      timeout = Time.now + 20 * 60  # 20 minutes
      while Time.now < timeout
        ipconfig_data = `ipconfig /all`
        match_result = ipconfig_data.match(/DHCP Server.*\: (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/)
        unless match_result.nil? || match_result[1].nil?
          return match_result[1]
        end
        # it may take time to resolve the DHCP Server for this instance, so sleepy wait.
        ::Ohai::Log.debug("ipconfig /all did not contain any DHCP Servers. Retrying in 10 seconds...")
        sleep 10
      end
    else
      leases_file = %w{/var/lib/dhcp/dhclient.eth0.leases /var/lib/dhcp3/dhclient.eth0.leases /var/lib/dhclient/dhclient-eth0.leases /var/lib/dhclient-eth0.leases /var/lib/dhcpcd/dhcpcd-eth0.info}.find{|dhcpconfig| File.exist?(dhcpconfig)}
      unless leases_file.nil?
        lease_file_content = File.read(leases_file)

        dhcp_lease_provider_ip = lease_file_content[/DHCPSID='(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'/, 1]
        return dhcp_lease_provider_ip unless dhcp_lease_provider_ip.nil?

        # leases are appended to the lease file, so to get the appropriate dhcp lease provider, we must grab
        # the info from the last lease entry.
        #
        # reverse the content and reverse the regex to find the dhcp lease provider from the last lease entry
        lease_file_content.reverse!
        dhcp_lease_provider_ip = lease_file_content[/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}) reifitnedi-revres-pchd/, 1]
        return dhcp_lease_provider_ip.reverse unless dhcp_lease_provider_ip.nil?
      end
    end
    # no known defaults so we must fail at this point.
    raise "Cannot determine dhcp lease provider for cloudstack instance"
  end

  def can_metadata_connect?(addr, port, timeout=2)
    t = Socket.new(Socket::Constants::AF_INET, Socket::Constants::SOCK_STREAM, 0)
    saddr = Socket.pack_sockaddr_in(port, addr)
    connected = false

    begin
      t.connect_nonblock(saddr)
    rescue Errno::EINPROGRESS
      r,w,e = IO::select(nil,[t],nil,timeout)
      if !w.nil?
        connected = true
      else
        begin
          t.connect_nonblock(saddr)
        rescue Errno::EISCONN
          t.close
          connected = true
        rescue SystemCallError
        end
      end
    rescue SystemCallError
    end
    ::Ohai::Log.debug("can_metadata_connect? == #{connected}")
    connected
  end
end


module ::Ohai::Mixin::AzureMetadata
  include ::Ohai::Mixin::ShouldBeRenamed

  def query_url(url)
    u = URI(url) # doesn't work on 1.8.7 didn't figure out why
    req = Net::HTTP::Get.new(u.request_uri)
    req['x-ms-agent-name'] = 'WALinuxAgent'
    req['x-ms-version'] = '2012-11-30'

    res = Net::HTTP.start(u.hostname, u.port) {|http|
      http.request(req)
    }
    res.body
  end

  def fetch_metadata(host)
    base_url="http://#{host}"

    ::Ohai::Log.debug "Base url #{base_url}"

    res = query_url("#{base_url}/machine/?comp=goalstate")
    ::Ohai::Log.debug  "\ngoalstate\n------------------"
    ::Ohai::Log.debug  res
    container_id = res.match(/<ContainerId>(.*?)<\/ContainerId>/)[1]
    instance_id  = res.match(/<InstanceId>(.*?)<\/InstanceId>/)[1]
    incarnation = res.match(/<Incarnation>(.*?)<\/Incarnation>/)[1]

    ::Ohai::Log.debug "container_id #{container_id} instance_id #{instance_id} incarnation #{incarnation}"

    shard_config_content = query_url("#{base_url}/machine/#{container_id}/#{instance_id}?comp=config&type=sharedConfig&incarnation=#{incarnation}")
    ::Ohai::Log.debug "\nsharedConfig\n------------------"
    ::Ohai::Log.debug shard_config_content

    shared_config = SharedConfig.new shard_config_content

    {
      'public_ip'       => shared_config.public_ip,
      'vm_name'         => shared_config.vm_name,
      'public_fqdn'     => "#{shared_config.vm_name}.cloudapp.net",
      'public_ssh_port' => shared_config.public_ssh_port,
    }
  end

  class SharedConfig
    REQUIRED_ELEMENTS = ["*/Deployment", "*/*/Service", "*/*/ServiceInstance", "*/Incarnation", "*/Role" ]

    class InvalidConfig < StandardError; end

    def initialize(shard_config_content)
      @shared_config = REXML::Document.new shard_config_content
      raise InvalidConfig unless @shared_config.root.name == "SharedConfig"
      raise InvalidConfig unless REQUIRED_ELEMENTS.all? { |element| @shared_config.elements[element] }
    end

    def vm_name
      @vm_name ||= @shared_config.elements["SharedConfig/Deployment/Service"].attributes["name"] rescue nil
    end

    def private_ip
      @private_ip ||= @shared_config.elements["SharedConfig/Instances/Instance"].attributes["address"] rescue nil
    end

    def inputs_endpoints
      @inputs_endpoints ||= [].tap do |endpoints|
        endpoint = @shared_config.elements["SharedConfig/Instances/Instance/InputEndpoints/Endpoint"] rescue nil
        while endpoint
          endpoints << endpoint
          endpoint = endpoint.next_element
        end
        endpoints
      end
    end

    def ssh_endpoint
      @ssh_endpoint ||= inputs_endpoints.detect { |ep| ep.attributes["name"] == "SSH" } rescue nil
    end

    def first_public_endpoint
      @first_public_endpoint ||= inputs_endpoints.detect { |ep| ep.attributes['isPublic'] == 'true'} rescue nil
    end

    def public_ip
      @public_ip ||= first_public_endpoint.attributes["loadBalancedPublicAddress"].split(":").first rescue nil
    end

    def public_ssh_port
      @public_ssh_port ||= ssh_endpoint.attributes["loadBalancedPublicAddress"].split(":").last.to_i rescue nil
    end
  end
end

if __FILE__ == $0

  res = query_url("#{base_url}/?comp=versions")
  puts "\nversions\n------------------"
  puts res

  res = query_url("#{base_url}/machine/#{container_id}/#{instance_id}?comp=config&type=sharedConfig&incarnation=#{incarnation}")
  puts "\nsharedConfig\n------------------"
  puts res

  res = query_url("#{base_url}/machine/#{container_id}/#{instance_id}?comp=config&type=hostingEnvironmentConfig&incarnation=#{incarnation}")
  puts "\nhostingEnvironment\n------------------"
  puts res

  res = query_url("#{base_url}/machine/#{container_id}/#{instance_id}?comp=config&type=fullConfig&incarnation=#{incarnation}")
  puts "\nfullConfig\n------------------"
  puts res

  #res = query_url("#{base_url}/machine/#{container_id}/#{instance_id}?comp=certificates&incarnation=#{incarnation}")
  #puts "\ncertificates\n------------------"
  #puts res
end