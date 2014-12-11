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

module RightScale::Clouds
  class Softlayer < RightScale::Cloud
    def abbreviation
      "sl"
    end

    def metadata_host
      "https://api.service.softlayer.com"
    end

    def metadata_item(item)
      "/rest/v3/SoftLayer_Resource_Metadata/#{item}"
    end

    def userdata_url
      metadata_item("UserMetadata.txt")
    end

    def fetcher
      @fetcher ||= RightScale::MetadataSources::HttpMetadataSource.new(@options)
    end


    def finish
      @fetcher.finish() if @fetcher
    end

    def metadata
      metadata  = {
        'public_fqdn'   => fetcher.get(metadata_item("getFullyQualifiedDomainName.txt")),
        'local_ipv4'    => fetcher.get(metadata_item("getPrimaryBackendIpAddress.txt")),
        'public_ipv4'   => fetcher.get(metadata_item("getPrimaryIpAddress.txt")),
        'region'        => fetcher.get(metadata_item("getDatacenter.txt")),
        'instance_id'   => fetcher.get(metadata_item("getId.txt"))
      }

      metadata
    end

    def userdata_raw
      fetcher.get(userdata_url)    
    end
  end
end

