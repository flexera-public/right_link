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

require 'logger'

module RightScale
  module Test

    # mocks the AuditorProxy class used by RightLink for testing.
    class MockAuditorProxy < Logger
      def initialize
        super(nil)
        @debug_text = ""
        @error_text = ""
        @fatal_text = ""
        @info_text = ""
        @warn_text = ""
      end

      attr_reader :debug_text, :error_text, :fatal_text, :info_text, :warn_text

      def ensure_newline(message)
        return "#{message.chomp}\n"
      end

      def append_debug(message)
        @debug_text << ensure_newline(message)
      end

      def append_error(message)
        @error_text << ensure_newline(message)
      end

      def append_fatal(message)
        @fatal_text << ensure_newline(message)
      end

      def append_info(message)
        @info_text << ensure_newline(message)
      end

      def append_output(message)
        @info_text << ensure_newline(message)
      end

      def append_warn(message)
        @warn_text << ensure_newline(message)
      end

      def add(severity, message = nil, progname = nil, &block)
        severity ||= Logger::UNKNOWN
        if severity < @level
          return true
        end
        progname ||= @progname
        if message.nil?
          if block
            message = block.call
          else
            message = progname
            progname = @progname
          end
        end

        case severity
        when Logger::DEBUG then append_debug(message)
        when Logger::ERROR then append_error(message)
        when Logger::FATAL then append_fatal(message)
        when Logger::INFO then append_info(message)
        when Logger::WARN then append_warn(message)
        end

        true
      end
    end
  end
end
