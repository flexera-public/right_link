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

require 'socket'
require 'uri'

module ::Ohai::Mixin::CloudstackMetadata

  # Searches for a file containing dhcp lease information.
  def dhcp_lease_provider
    if RUBY_PLATFORM =~ /mswin|mingw|windows/
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

  def http_client(host)
    Net::HTTP.start(host).tap {|h| h.read_timeout = 600}
  end

  def fetch_metadata(host)
    client = http_client(host)
    metadata = Hash.new
    %w{service-offering availability-zone local-ipv4 local-hostname public-ipv4 public-hostname instance-id}.each do |id|
      name = id.gsub(/\-|\//, '_')
      value = metadata_get(id, client)
      metadata[name] = value
    end
    metadata
  end

  # Get metadata for a given path
  #
  # @details
  #   Typically, a 200 response is expected for valid metadata.
  #   On certain instance types, traversing the provided metadata path
  #   produces a 404 for some unknown reason. In that event, return
  #   `nil` and continue the run instead of failing it.
  def metadata_get(id, http_client)
    path = "/latest/#{id}"
    response = http_client.get(path)
    case response.code
    when '200'
      response.body
    when '404'
      Ohai::Log.debug("Encountered 404 response retreiving Cloudstack metadata path: #{path} ; continuing.")
      nil
    else
      raise "Encountered error retrieving Cloudstack metadata (#{path} returned #{response.code} response)"
    end
  end

end