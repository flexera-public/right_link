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

require 'chef/log'

module RightScale
  module Mixin
    module Command

      # Runs the given command logging the output.
      #
      # === Parameters
      # command(String):: command to execute
      #
      # == Returns
      # status(String):: result of running script
      def execute(command)
        @execute_mutex        = Mutex.new
        @execute_exited_event = ConditionVariable.new
        @execute_status       = nil

        ::Chef::Log.debug("Executing \"#{command}\"")

        @execute_mutex.synchronize do
          RightScale.popen3(command, self, :on_read_stdout, :on_read_stderr, :on_exit)
          @execute_exited_event.wait(@execute_mutex)
        end

        return @execute_status
      end

      # Data available in STDOUT pipe event
      # Audit raw output
      #
      # === Parameters
      # data(String):: STDOUT data
      #
      # === Return
      # true:: Always return true
      def on_read_stdout(data)
        ::Chef::Log.info(data)
      end

      # Data available in STDERR pipe event
      # Audit error
      #
      # === Parameters
      # data(String):: STDERR data
      #
      # === Return
      # true:: Always return true
      def on_read_stderr(data)
        ::Chef::Log.error(data)
      end

      # Process exited event
      # Record duration and process exist status and signal Chef thread so it can resume
      #
      # === Parameters
      # status(Process::Status):: Process exit status
      #
      # === Return
      # true:: Always return true
      def on_exit(status)
        @execute_mutex.synchronize do
          @execute_status = status
          @execute_exited_event.signal
        end
        true
      end

    end
  end
end
