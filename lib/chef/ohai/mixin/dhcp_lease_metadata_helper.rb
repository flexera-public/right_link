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
require 'socket'

module ::Ohai::Mixin::DhcpLeaseMetadataHelper


  def lease_file_locations
    %w{
      /var/lib/dhclient/dhclient--eth0.lease 
      /var/lib/dhcp/dhclient.eth0.leases 
      /var/lib/dhcp3/dhclient.eth0.leases 
      /var/lib/dhclient/dhclient-eth0.leases 
      /var/lib/dhclient-eth0.leases 
      /var/lib/dhcpcd/dhcpcd-eth0.info
    }
  end

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
      leases_file = lease_file_locations.find { |dhcpconfig| File.exist?(dhcpconfig) }
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
