#
# Copyright (c) 2012 RightScale Inc
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

# host/port are constants for Google Compute Engine.
module RightScale::Clouds
  class Gce < RightScale::Cloud
    def abbreviation
      "gce"
    end

    def metadata_host
      "http://metadata.google.internal"
    end

    def metadata_url
      "/0.1/meta-data/"
    end

    def userdata_url
      "/0.1/meta-data/attributes/"
    end

    def http_headers
       { "Metadata-Flavor" => "Google" }
    end

    def fetcher
      options = @options.merge({
        headers => http_headers, 
        :skip => [/auth.token/]
      })
      @fetcher ||= RightScale::MetadataSources::HttpMetadataSource.new(options)
    end

    def finish
      @fetcher.finish() if @fetcher
    end

    def metadata
      metadata = fetcher.recursive_get(metadata_host + metadata_url)
      # Filter out rightscale userdata keys, we get those for userdata below
      if metadata && metadata['attributes']
        rs_keys = metadata['attributes'].keys.select { |key| key =~ /^RS_/i }
        rs_keys.each { |k| metadata['attributes'].delete(k)}
      end 
      metadata
    end

    def userdata
      fetcher.recursive_get(userdata_url)
    end

    def userdata_raw
      userdata_hash = userdata
      userdata_raw = ""
      userdata_hash.keys.sort.each do |k|
        userdata_raw << "#{k}=#{userdata_hash[k]}&"
      end
      userdata_raw.chomp("&")
    end
  end
end
