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

begin
  require 'chef'
rescue LoadError => e
  File.open('/tmp/chef_log-insanity', 'a') do |f|
    f.puts "Why in the world does this load error only happen in CI?"
    f.puts e.message
    f.puts $:.join("\n")
    puts "Why in the world does this load error only happen in CI?"
    puts e.message
    puts $:.join("\n")
    raise e
  end
end

class Chef
  module Mixin

    # monkey patch for Chef::Mixin::Command module which is Linux-only.
    module Command

      # Executes the given command while monitoring stdout and stderr for the
      # child process.
      #
      # === Parameters
      # args(Hash):: A number of required and optional arguments, as follows:
      #
      # command(String or Array):: A complete command with options to execute or a command and options as an Array (required).
      # creates(String):: The absolute path to a file that prevents the command from running if it exists (defaults to nil).
      # cwd(String): Working directory to execute command in (defaults to Dir.tmpdir).
      # returns(Array): Array of exit values command is expected to return, otherwise causes an exception (defaults to zero).
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

        run_started_at = Time.now
        status         = nil
        ::Dir.chdir(args[:cwd]) do
          status = execute(args[:command], args[:environment])
        end
        duration = Time.now - run_started_at
        ::Chef::Log.info("Script duration: #{duration}")

        unless args[:ignore_failure]
          args[:returns] ||= [ 0 ]
          args[:returns] = [ args[:returns] ] unless args[:returns].is_a?(Array)
          if !args[:returns].include?(status.exitstatus)
            raise RightScale::Exceptions::Exec.new("\"#{args[:command]}\" returned #{status.exitstatus}, expected #{args[:returns].join(' or ')}.", args[:cwd])
          end
        end

        status
      end

      module_function :run_command

      # Runs the given command logging the output.
      #
      # === Parameters
      # command(String):: command to execute
      # env(Hash):: Hash of environment variables values keyed by name, optional
      #             Note: not supported on Windows atm
      #
      # == Returns
      # status(String):: result of running script
      def execute(command, env=nil)
        return RightPopenExecutor.new.execute(command, env)
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

        def execute(command, env=nil)
          ::Chef::Log.debug("Executing \"#{command}\"")

          @execute_mutex.synchronize do
            RightScale.popen3(:command        => command,
                              :environment    => env,
                              :target         => self,
                              :stdout_handler => :on_read_output,
                              :stderr_handler => :on_read_output,
                              :exit_handler   => :on_exit,
                              :temp_dir       => RightScale::InstanceConfiguration::CACHE_PATH)
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
        def on_read_output(data)
          ::Chef::Log.info(data)
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
