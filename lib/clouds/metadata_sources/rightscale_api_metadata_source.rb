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

require File.expand_path("../file_metadata_source", __FILE__)

# Both "blue-skies" cloud and "wrap instance" behave the same way, they lay down a
# file in a predefined location (/var/spool/rightscale/user-data.txt on linux,
# C:\ProgramData\RightScale\spool\rightscale\user-data.txt on windows). In both
# cases this userdata has *lower* precedence than cloud data. On a start/stop
# action where userdata is updated, we want the NEW userdata, not the old. So
# if cloud-based values exist, than use those.
module RightScale

  module MetadataSources

    # Provides metadata by reading a dictionary file on disk.
    class RightScaleApiMetadataSource < FileMetadataSource
      FILE_PATH =  File.join(RightScale::Platform.filesystem.spool_dir, 'rightscale', 'user-data.txt')

      def initialize(options = {})
        options[:file_path] =
        super(options)
      end

      def source_exists?
        ::File.exists?(FILE_PATH)
      end

      # Queries for metadata using the given path.
      #
      # === Parameters
      # path(String):: metadata path
      #
      # === Return
      # metadata(String):: query result or empty
      #
      # === Raises
      # QueryFailed:: on any failure to query
      def get
        begin
          result = ::File.read(FILE_PATH)
        rescue Exception => e
          raise QueryFailed.new(e.message)
        end
      end

    end  # RightScaleApiMetadataSource

  end  # MetadataSources

end  # RightScale
