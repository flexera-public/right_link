#
# Copyright (c) 2012-2013 RightScale Inc
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

# set abbreviation for env var generation to be same as legacy Rackspace for scripters.
abbreviation :rax

# extend legacy Rackspace cloud definition. currently there are no differences aside from name.
extend_cloud :rackspace

# Updates the given node with cloudstack details.
#
# === Return
# always true
def update_details
  details = {}
  if ohai = @options[:ohai_node]
    if platform.windows?
      details[:public_ip] = ::RightScale::CloudUtilities.ip_for_windows_interface(ohai, 'public')
      details[:private_ip] = ::RightScale::CloudUtilities.ip_for_windows_interface(ohai, 'private')
    else
      details[:public_ip] = ::RightScale::CloudUtilities.ip_for_interface(ohai, :eth0)
      details[:private_ip] = ::RightScale::CloudUtilities.ip_for_interface(ohai, :eth1)
    end
  end

  # rack_connect (and managed?) instances may not have network interfaces for
  # public ip, so attempt the "what's my ip?" method in these cases.
  unless details[:public_ip]
    if public_ip = ::RightScale::CloudUtilities.query_whats_my_ip(:logger=>logger)
      details[:public_ip] = public_ip
    end
  end

  return details
end
