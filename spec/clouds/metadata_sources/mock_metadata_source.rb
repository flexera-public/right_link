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


module RightScale

  module MetadataSources

    # Mocks a metadata source for testing.
    class MockMetadataSource < MetadataSource

      attr_accessor :mock_metadata, :finished

      CLOUD_METADATA = {'ABC' => 'easy', 'abc_123' => {'baby' => "you" }}
      CLOUD_USERDATA = "RS_RN_ID=12345&RS_SERVER=my.rightscale.com"

      def initialize(options)
        @finished = false
      end

      def get_metadata(override = nil)
        raise QueryFailed.new("already finished") if @finished
        return override || CLOUD_METADATA
      end

      def get_userdata(override = nil)
        raise QueryFailed.new("already finished") if @finished
        return override || CLOUD_USERDATA
      end

      def finish
        @finished = true
      end

    end  # MockMetadataSource

  end  # MetadataSources

end  # RightScale
