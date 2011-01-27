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

provides "cloudstack"

if RightScale::CloudUtilities.is_cloud?(:cloudstack)
  require_plugin "#{os}::cloudstack"

  if cloudstack != nil && RightScale::CloudUtilities.can_contact_metadata_server?(cloudstack[:dhcp_lease_provider_ip], 80)
    cloudstack.update(RightScale::CloudUtilities.metadata("http://#{cloudstack[:dhcp_lease_provider_ip]}/latest", %w{service-offering availability-zone local-ipv4 local-hostname public-ipv4 public-hostname instance-id}))
    cloudstack[:userdata] = RightScale::CloudUtilities.userdata("http://#{cloudstack[:dhcp_lease_provider_ip]}/latest/user-data")
  else
    cloudstack nil
  end
end
