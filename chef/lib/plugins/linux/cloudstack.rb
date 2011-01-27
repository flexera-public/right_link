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

leases_file = %w{/var/lib/dhcp3/dhclient.eth0.leases /var/lib/dhclient/dhclient-eth0.leases /var/lib/dhclient-eth0.leases}.find{|dhcpconfig| File.exist?(dhcpconfig)}
unless leases_file.nil?
  lease_file_content = File.read(leases_file)
  provider_line = lease_file_content.match(/dhcp-server-identifier (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/)

  unless provider_line.nil? || provider_line[1].nil?
    cloudstack Mash.new
    cloudstack[:dhcp_lease_provider_ip] = provider_line[1]
  end
end
