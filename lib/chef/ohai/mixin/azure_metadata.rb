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
require 'chef/ohai/mixin/dhcp_lease_metadata_helper'

module ::Ohai::Mixin::AzureMetadata
  include ::Ohai::Mixin::DhcpLeaseMetadataHelper

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

    goalstate = query_url("#{base_url}/machine/?comp=goalstate")
    container_id = goalstate.match(/<ContainerId>(.*?)<\/ContainerId>/)[1]
    instance_id  = goalstate.match(/<InstanceId>(.*?)<\/InstanceId>/)[1]
    incarnation = goalstate.match(/<Incarnation>(.*?)<\/Incarnation>/)[1]

    ::Ohai::Log.debug  "\ngoalstate\n------------------"
    ::Ohai::Log.debug  goalstate
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

end