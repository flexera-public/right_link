#
# Copyright (c) 2010 RightScale Inc
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
  module Test
    module MockAuditorProxy
      extend self

      def mock_chef_log(logger)
        flexmock(Chef::Log).should_receive(:debug).and_return { |m| logger.debug_text << m }
        flexmock(Chef::Log).should_receive(:error).and_return { |m| logger.error_text << m }
        flexmock(Chef::Log).should_receive(:fatal).and_return { |m| logger.fatal_text << m }
        flexmock(Chef::Log).should_receive(:info).and_return { |m| logger.info_text << m }
        flexmock(Chef::Log).should_receive(:warn).and_return { |m| logger.warn_text << m }
        flexmock(Chef::Log.logger).should_receive(:create_new_section).and_return { |m| }
      end

      def mock_right_link_log(logger)
        flexmock(RightScale::RightLinkLog).should_receive(:debug).and_return { |m| logger.debug_text << m }
        flexmock(RightScale::RightLinkLog).should_receive(:error).and_return { |m| logger.error_text << m }
        flexmock(RightScale::RightLinkLog).should_receive(:fatal).and_return { |m| logger.fatal_text << m }
        flexmock(RightScale::RightLinkLog).should_receive(:info).and_return { |m| logger.info_text << m }
        flexmock(RightScale::RightLinkLog).should_receive(:warn).and_return { |m| logger.warn_text << m }
      end
    end

    class MockLogger
      attr_accessor :debug_text, :error_text, :fatal_text, :info_text, :warn_text,
                    :audit_info, :audit_output, :audit_status, :audit_section

      def initialize
        @debug_text = ""
        @error_text = ""
        @fatal_text = ""
        @info_text = ""
        @warn_text = ""
        @audit_info = ""
        @audit_output = ""
        @audit_status = ""
        @audit_section = ""
      end
    end
  end
end
