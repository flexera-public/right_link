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

require 'chef/mixin/command'
require 'chef/log'
require 'chef/provider'

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'mixin', 'command'))

class Chef
  class Provider
    class Win32Execute < Chef::Provider

      include Chef::Mixin::Command
      include RightScale::Mixin::Command

      # No concept of a 'current' resource for execution, this is a no-op
      #
      # === Return
      # true:: Always return true
      def load_current_resource
        true
      end

      # Runs the command from the resource. Attempts to be faithful to the Linux
      # implementation of the Chef execute/shell provider, but not all of the
      # functionality is portable.
      #
      # Relies on RightScale::popen3 to spawn process and receive both standard
      # and error outputs. Synchronizes with EM thread so that execution is
      # synchronous even though RightScale::popen3 is asynchronous.
      #
      # === Return
      # true:: Always return true
      #
      # === Raises
      # RightScale::Exceptions::Exec:: on failure to execute
      def action_run
        command_args = { }
        
        command_args[:command]        = @new_resource.command
        command_args[:command_string] = @new_resource.to_s
        command_args[:creates]        = @new_resource.creates if @new_resource.creates
        command_args[:only_if]        = @new_resource.only_if if @new_resource.only_if
        command_args[:not_if]         = @new_resource.not_if if @new_resource.not_if
        command_args[:returns]        = @new_resource.returns if @new_resource.returns
        command_args[:environment]    = @new_resource.environment if @new_resource.environment
        command_args[:cwd]            = @new_resource.cwd if @new_resource.cwd

        status = win32_run_command(command_args)
        if status
          @new_resource.updated = true
        end
        true
      end

      protected

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
      def win32_run_command(args={})
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

    end
  end
end

# self-register
Chef::Platform.platforms[:windows][:default].merge!(:execute => Chef::Provider::Win32Execute)
