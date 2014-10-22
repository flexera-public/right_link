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

require 'chef/ohai/mixin/rightlink'


Ohai.plugin(:Softlayer) do
  include ::Ohai::Mixin::RightLink::CloudUtilities

  provides 'softlayer'
  depends 'network'

  def looks_like_softlayer?
    looks_like_softlayer = !!hint?('softlayer')
    ::Ohai::Log.debug("looks_like_softlayer? == #{looks_like_softlayer.inspect} ")
    looks_like_softlayer
  end

  collect_data do
    if looks_like_softlayer?
      softlayer Mash.new
      softlayer['local_ipv4'] = private_ips(network).first
      softlayer['public_ipv4'] = public_ips(network).first
      softlayer['private_ips'] = private_ips(network)
      softlayer['public_ips'] = public_ips(network)
    end
  end
end
