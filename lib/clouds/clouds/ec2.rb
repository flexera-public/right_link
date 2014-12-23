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
  class Ec2 < RightScale::Cloud
    def abbreviation
      "ec2"
    end

    def metadata_host
      "http://169.254.169.254"
    end

    def metadata_url
      "/latest/meta-data"
    end

    def userdata_url
      "/latest/user-data"
    end

    def fetcher
      @fetcher ||= RightScale::MetadataSources::HttpMetadataSource.new(@options)
    end

    def finish
      @fetcher.finish() if @fetcher
    end

    def metadata
      fetcher.recursive_get(metadata_host + metadata_url)
    end

    def userdata_raw
      fetcher.get(metadata_host + userdata_url)    
    end
  end
end
