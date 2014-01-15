#
# Copyright (c) 2010-2011 RightScale Inc
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

module ::Ohai::Mixin::CloudstackMetadata
  def fetch_metadata
    options = {}
    options[:logger] = ::Ohai::Log
    cloud_instance = ::RightScale::CloudFactory.instance.create('cloudstack', options)
    metadata = cloud_instance.build_metadata(:cloud_metadata)
    hosts = cloud_instance.option('metadata_source/hosts')
    metadata[:dhcp_lease_provider_ip] = hosts.first[:host]
    metadata
  end
end

extend ::Ohai::Mixin::CloudstackMetadata

def looks_like_cloudstack?
  hint?('cloudstack')
end

if looks_like_cloudstack?
  ::Ohai::Log.debug('looks_like_cloudstack? == true')
  cloudstack Mash.new
  fetch_metadata.each { |k,v| cloudstack[k] = v }
else
  ::Ohai::Log.debug('looks_like_cloudstack? == false')
  false
end