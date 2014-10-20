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
require 'socket'
require 'net-dhcp'
require 'timeout'

class NoOption245Error < Exception; end


module ::Ohai::Mixin::AzureMetadata

  class SharedConfig
    REQUIRED_ELEMENTS = ["*/Deployment", "*/*/Service", "*/*/ServiceInstance", "*/Incarnation", "*/Role" ]

    class InvalidConfig < StandardError; end

    def initialize(shared_config_content)
      @shared_config = REXML::Document.new shared_config_content
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

    def rdp_endpoint
      @rdp_endpoint ||= inputs_endpoints.detect { |ep| ep.attributes["name"] == "RDP" } rescue nil
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

    def public_winrm_port
      @public_winrm_port ||= rdp_endpoint.attributes["loadBalancedPublicAddress"].split(":").last.to_i rescue nil
    end
  end

  def query_url(url)
    begin
      u = URI(url) # doesn't work on 1.8.7 didn't figure out why
      req = Net::HTTP::Get.new(u.request_uri)
      req['x-ms-agent-name'] = 'WALinuxAgent'
      req['x-ms-version'] = '2012-11-30'

      res = Net::HTTP.start(u.hostname, u.port) {|http|
        http.request(req)
      }
      res.body
    rescue Exception => e
      ::Ohai::Log.debug("Unable to fetch azure metadata from #{url}: #{e.class}: #{e.message}")
    end
  end


  # Azure cloud has a metadata service (called the fabric controller). The ip of this
  # is passed in the response to DHCP discover packet as option 245. Proceed to 
  # query the DHCP server, then parse its response for that option
  # See WALinuxAgent project as a reference, which does a bit more:
  #   - add then remove default route
  #   - disable then re-enable wicked-dhcp4 for distros that use it
  def build_dhcp_request
    req = DHCP::Discover.new
    ::Ohai::Log.debug(req)
    req.pack
  end

  def endpoint_from_response(raw_pkt)
    packet = DHCP::Message.from_udp_payload(raw_pkt, :debug => false)
    ::Ohai::Log.debug("Received response from Azure DHCP server:\n" + packet.to_s)
    option = packet.options.find { |opt| opt.type == 245 }
    if option
      return option.payload.join(".")
    else
      raise NoOption245Error
    end
  end

  def send_dhcp_request
    begin
      dhcp_send_packet = build_dhcp_request()

      sock = UDPSocket.new
      sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
      sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
      sock.bind('0.0.0.0', 68)
      sock.send(dhcp_send_packet, 0, '<broadcast>', 67)

      dhcp_rcv_packet = Timeout::timeout(10) { sock.recv(1024) }
      return dhcp_rcv_packet
    ensure
      sock.close() if sock && !sock.closed?
    end
  end

  def azure_fabric_controller_ip
    return @azure_endpoint if @azure_endpoint
    3.times do
      begin
        dhcp_res_pkt = send_dhcp_request()
        @azure_endpoint = endpoint_from_response(dhcp_res_pkt)
      rescue NoOption245Error => e
        raise "No option 245 in DHCP response, we don't appear to be in the Azure cloud"
      rescue Exception => e
        # no-op for timeout
      end
      break if @azure_endpoint
    end
    raise "Could not get Azure endpoint" unless @azure_endpoint
    @azure_endpoint
  end

  def fetch_azure_metadata

    base_url="http://#{azure_fabric_controller_ip}"

    ::Ohai::Log.debug "Base url #{base_url}"

    goalstate = query_url("#{base_url}/machine/?comp=goalstate")
    container_id = goalstate.match(/<ContainerId>(.*?)<\/ContainerId>/)[1]
    instance_id  = goalstate.match(/<InstanceId>(.*?)<\/InstanceId>/)[1]
    incarnation = goalstate.match(/<Incarnation>(.*?)<\/Incarnation>/)[1]

    ::Ohai::Log.debug  "\ngoalstate\n------------------"
    ::Ohai::Log.debug  goalstate
    ::Ohai::Log.debug "container_id #{container_id} instance_id #{instance_id} incarnation #{incarnation}"

    shared_config_content = query_url("#{base_url}/machine/#{container_id}/#{instance_id}?comp=config&type=sharedConfig&incarnation=#{incarnation}")
    ::Ohai::Log.debug "\nsharedConfig\n------------------"
    ::Ohai::Log.debug shared_config_content

    shared_config = SharedConfig.new shared_config_content


    metadata = {
      'public_ip'       => shared_config.public_ip,
      'private_ip'      => shared_config.private_ip,
      'vm_name'         => shared_config.vm_name,
      'public_fqdn'     => "#{shared_config.vm_name}.cloudapp.net"
    }

    metadata['public_ssh_port'] = shared_config.public_ssh_port if shared_config.public_ssh_port
    metadata['public_winrm_port'] = shared_config.public_winrm_port if shared_config.public_winrm_port
    metadata

  end
end
