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

provides 'azure'

require 'chef/ohai/mixin/rightlink'
require_plugin 'hostname'

def looks_like_azure?
  looks_like_azure = hint?('azure')
  ::Ohai::Log.warn("looks_like_azure? == #{looks_like_azure.inspect} ")
  looks_like_azure
end


if looks_like_azure?
  azure Mash.new
  azure['public_ip'] = ::Ohai::Mixin::RightLink::CloudUtilities.query_whats_my_ip(:logger=>::Ohai::Log)
  azure['vm_name'] = self['hostname'] if self['hostname']
  azure['public_fqdn'] = "#{self['hostname']}.cloudapp.net" if self['hostname']

end