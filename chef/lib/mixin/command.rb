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
require 'chef/mixin/command'

class Chef
  module Mixin

    # monkey patch for Chef::Mixin::Command module which is Linux-only.
    module Command

      # If command is a block, returns true if the block returns true, false if it returns false.
      # ("Only run this resource if the block is true")
      #
      # If the command is not a block, executes the command.  If it returns any status other than
      # 0, it returns false (clearly, a 0 status code is true)
      #
      # === Parameters
      # command<Block>, <String>:: A block to check, or a string to execute
      #
      # === Returns
      # true:: Returns true if the block is true, or if the command returns 0
      # false:: Returns false if the block is false, or if the command returns a non-zero exit code.
      def only_if(command)
        if command.kind_of?(Proc)
          res = command.call
          unless res
            return false
          end
        else
          status = run_command(:command => command, :ignore_failure => true)
          if status.exitstatus != 0
            return false
          end
        end
        true
      end

      module_function :only_if

      # If command is a block, returns false if the block returns true, true if it returns false.
      # ("Do not run this resource if the block is true")
      #
      # If the command is not a block, executes the command.  If it returns a 0 exitstatus, returns false.
      # ("Do not run this resource if the command returns 0")
      #
      # === Parameters
      # command<Block>, <String>:: A block to check, or a string to execute
      #
      # === Returns
      # true:: Returns true if the block is false, or if the command returns a non-zero exit status.
      # false:: Returns false if the block is true, or if the command returns a 0 exit status.
      def not_if(command)
        if command.kind_of?(Proc)
          res = command.call
          if res
            return false
          end
        else
          status = run_command(:command => command, :ignore_failure => true)
          if status.exitstatus == 0
            return false
          end
        end
        true
      end

      module_function :not_if

      # Executes the given command while monitoring stdout and stderr for the
      # child process.
      #
      # === Parameters
      # args(Hash):: A number of required and optional arguments, as follows:
      #
      # command(String or Array):: A complete command with options to execute or a command and options as an Array (required).
      # creates(String):: The absolute path to a file that prevents the command from running if it exists (defaults to nil).
      # cwd(String): Working directory to execute command in (defaults to Dir.tmpdir).
      # returns(String): The single exit value command is expected to return, otherwise causes an exception (defaults to zero).
      # ignore_failure(Boolean): true to return the failed status, false to raise an exception on failure (defaults to false).
      # environment(Hash): Pairs of environment variable names and their values to set before execution (defaults to empty).
      #
      # === Returns
      # status(Status): Returns the exit status of the command.
      #
      # === Raises
      # RightScale::Exceptions::Exec:: on failure to execute
      def run_command(args={})
        args[:ignore_failure] ||= false

        if args.has_key?(:creates)
          if ::File.exists?(args[:creates])
            Chef::Log.debug("Skipping #{args[:command]} - creates #{args[:creates]} exists.")
            return false
          end
        end

        args[:cwd] ||= ::Dir.tmpdir
        unless ::File.directory?(args[:cwd])
          raise RightScale::Exceptions::Exec, "#{args[:cwd]} does not exist or is not a directory"
        end

        status = nil
        ::Dir.chdir(args[:cwd]) do
          status = execute(args[:command])
        end

        unless args[:ignore_failure]
          args[:returns] ||= 0
          if status.exitstatus != args[:returns]
            raise RightScale::Exceptions::Exec, "\"#{args[:command]}\" returned #{status.exitstatus}, expected #{args[:returns]}"
          end
        end
        status
      end

      module_function :run_command

      # Runs the given command logging the output.
      #
      # === Parameters
      # command(String):: command to execute
      #
      # == Returns
      # status(String):: result of running script
      def execute(command)
        return RightPopenExecutor.new.execute(command)
      end

      module_function :execute

      protected

      # need an object to hold member variables because this mixin is both
      # included in classes and invoked directly.
      class RightPopenExecutor
        def initialize
          @execute_mutex        = Mutex.new
          @execute_exited_event = ConditionVariable.new
          @execute_status       = nil
        end

        def execute(command)
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
end
