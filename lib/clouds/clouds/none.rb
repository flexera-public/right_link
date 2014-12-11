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

# host/port are constants for Google Compute Engine.
module RightScale::Clouds
  class None < RightScale::Cloud
    def abbreviation
      "none"
    end

    def metadata_file
      File.join(RightScale::Platform.filesystem.spool_dir, 'none', 'meta-data.txt')
    end

    def userdata_file
      File.join(RightScale::Platform.filesystem.spool_dir, 'none', 'user-data.txt')
    end

    def fetcher
      @fetcher ||= RightScale::MetadataSources::FileMetadataSource.new(@options)
    end


    def metadata
      if ::File.exists?(metadata_file)
        fetcher.get(metadata_file)
      else
        nil
      end
    end

    def userdata_raw
      if ::File.exists?(userdata_file)
        fetcher.get(userdata_file)
      else
        nil
      end
    end
  end
end
