#
# Copyright (c) 2013 RightScale Inc
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
require 'fileutils'

module RightScale::Clouds
  class Vsphere < RightScale::Cloud
    VSCALE_DEFINITION_VERSION = 0.3

    def abbreviation
      "vs"
    end

    def vsphere_metadata_location
      File.join(RightScale::Platform.filesystem.spool_dir, 'vsphere')
    end

    def metadata_file
      File.join(vsphere_metadata_location, "meta.txt")
    end

    def userdata_file
      File.join(vsphere_metadata_location, "user.txt")
    end

    def fetcher
      @fetcher ||= RightScale::MetadataSources::FileMetadataSource.new(@options)
    end

    def metadata
      data = fetcher.get(metadata_file)
      RightScale::CloudUtilities.split_metadata(data, "\n", "=")
    end

    def userdata_raw
      raw_data = fetcher.get(userdata_file)
      raw_data.split("\n").join("&")
    end

    def requires_network_config?
      true
    end

    def finish
      @fetcher.finish() if @fetcher
    end
  end
end

