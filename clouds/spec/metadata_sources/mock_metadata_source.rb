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

      def initialize(options)
        raise "options[:mock_metadata] is required" unless @mock_metadata = options[:mock_metadata]
        @finished = false
      end

      def query(path)
        raise QueryFailed.new("already finished") if @finished
        # example: @mock_metadata.self['cloud metadata']['ABC']
        eval_me = "self['#{path.split('/').join("']['")}']"
        data = @mock_metadata.instance_eval(eval_me)
        raise QueryFailed.new("Unexpected metadata path = #{path.inspect}") unless data
        if data.respond_to?(:has_key?)
          listing = []
          data.each do |key, value|
            ending = value.respond_to?(:has_key?) ? '/' : ''
            listing << "#{key}#{ending}"
          end
          return listing.join("\n")
        else
          return data
        end
      end

      def finish
        @finished = true
      end

    end  # MockMetadataSource

  end  # MetadataSources

end  # RightScale
