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
      metadata_raw = fetcher.get(metadata_file)
      parse_metadata(metadata_raw)
    end

    def userdata_raw
      fetcher.get(metadata_file)
    end

    def parse_metadata(data)
      RightScale::CloudUtilities.parse_rightscale_userdata(data)
    end


    def requires_network_config?
      true
    end

    def finish
      @fetcher.finish() if @fetcher
    end

    # Extend clear_state method
    # Clear any fetched metadata files
    # def clear_state
    #   super
    #   FileUtils.rm_rf(vsphere_metadata_locations) if File.directory?(vsphere_metadata_locations)
    # end


  end
end

