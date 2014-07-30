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

require 'uri'
require 'chef/ohai/mixin/dhcp_lease_metadata_helper'

module ::Ohai::Mixin::CloudstackMetadata
  include ::Ohai::Mixin::DhcpLeaseMetadataHelper

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