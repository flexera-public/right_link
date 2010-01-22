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

require 'fileutils'
require 'right_popen'  # now an intalled gem

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'mixin', 'command'))

class Chef

  class Provider

    # Powershell chef provider.
    class Powershell < Chef::Provider

      include RightScale::Mixin::Command

      # use a unique dir name instead of cluttering temp directory with leftover
      # scripts like the original script provider.
      SCRIPT_TEMP_DIR_PATH = ::File.join(::Dir.tmpdir, "chef-powershell-06D9AC00-8D64-4213-A46A-611FBAFB4426")

      # No concept of a 'current' resource for Powershell execution, this is a no-op
      #
      # === Return
      # true:: Always return true
      def load_current_resource
        true
      end

      # Actually run Powershell
      # Rely on RightScale::popen3 to spawn process and receive both standard and error outputs.
      # Synchronize with EM thread so that execution is synchronous even though RightScale::popen3 is asynchronous.
      #
      # === Return
      # true:: Always return true
      #
      # === Raise
      # RightScale::Exceptions::Exec:: Invalid process exit status
      def action_run
        run_started_at   = Time.now
        nickname         = @new_resource.name
        source           = @new_resource.source
        script_file_path = @new_resource.source_path
        parameters       = @new_resource.parameters
        current_state    = instance_state

        # 1. Write script source into file, if necessary.
        if script_file_path
          (raise RightScale::Exceptions::Exec, "Missing script file \"#{script_file_path}\"") unless ::File.file?(script_file_path)
        else
          FileUtils.mkdir_p(SCRIPT_TEMP_DIR_PATH)
          script_file_path = ::File.join(SCRIPT_TEMP_DIR_PATH, "powershell_provider_source.ps1")
          ::File.open(script_file_path, "w") { |f| f.write(source) }
        end

        begin
          # 2. Setup environment.
          parameters.each { |key, val| ENV[key] = val }
          ENV['RS_REBOOT'] = current_state.past_scripts.include?(nickname) ? '1' : nil

          # 3. execute and wait
          status = run_script_file(script_file_path)
          duration = Time.now - run_started_at

          # 4. Handle process exit status
          if status
            ::Chef::Log.info("Script exit status: #{status.exitstatus}")
          else
            ::Chef::Log.info("Script exit status: UNKNOWN; presumed success")
          end
          ::Chef::Log.info("Script duration: #{duration}")

          if !status || status.success?
            current_state.record_script_execution(nickname)
            @new_resource.updated = true
          else
            raise RightScale::Exceptions::Exec, "Powershell < #{nickname} > returned #{status.exitstatus}"
          end
        ensure
          (FileUtils.rm_rf(SCRIPT_TEMP_DIR_PATH) rescue nil) if ::File.directory?(SCRIPT_TEMP_DIR_PATH)
        end

        true
      end

      protected

      def instance_state
        RightScale::InstanceState
      end

      # Runs the given powershell script.
      #
      # === Parameters
      # script_file_path(String):: powershell script file path
      #
      # == Returns
      # result(Status):: result of running script
      def run_script_file(script_file_path)
        platform = RightScale::RightLinkConfig[:platform]
        shell    = platform.shell
        command  = shell.format_powershell_command(script_file_path)

        return execute(command)
      end

    end
  end
end

# self-register
Chef::Platform.platforms[:windows][:default].merge!(:powershell => Chef::Provider::Powershell)
