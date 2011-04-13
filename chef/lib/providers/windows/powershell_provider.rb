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
require 'chef/provider/execute'
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'windows', 'chef_node_server'))

class Chef

  class Provider

    # Powershell chef provider.
    class Powershell < Chef::Provider::Execute

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
        nickname         = @new_resource.name
        source           = @new_resource.source
        script_file_path = @new_resource.source_path
        environment      = @new_resource.environment
        current_state    = all_state

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
          environment = {} if environment.nil?
          environment['RS_ALREADY_RUN'] = current_state[:chef_state].past_scripts.include?(nickname) ? '1' : nil
          environment['RS_REBOOT'] = current_state[:cook_state].reboot?
          @new_resource.environment(environment)

          # 3. execute and wait
          RightScale::Windows::ChefNodeServer.instance.start(:node => node)

          # new_resource points to the powershell script resource in this limited
          # context. there is no current resource in script execution context.
          RightScale::Windows::ChefNodeServer.instance.new_resource = @new_resource

          command = format_command(script_file_path)
          @new_resource.command(command)
          ::Chef::Log.info("Running \"#{nickname}\"")
          super

          # super provider raises an exception on failure, so record success at
          # this point.
          current_state[:chef_state].record_script_execution(nickname)
          @new_resource.updated_by_last_action(true)

          # a script may have requested reboot via rs_shutdown command line
          # tool. if the script requested immediate shutdown then we must call
          # exit here to interrupt the Chef converge (assuming any subsequent
          # boot recipes are pending). otherwise, defer shutdown until scripts/
          # recipes finish or another script escalates to an immediate shutdown.
          exit 0 if RightScale::Cook.instance.shutdown_request.immediately?
        ensure
          (FileUtils.rm_rf(SCRIPT_TEMP_DIR_PATH) rescue nil) if ::File.directory?(SCRIPT_TEMP_DIR_PATH)
        end

        true
      end

      protected

      TEMP_DIR_NAME = 'powershell_provider-B6169A26-91B5-4e3e-93AD-F0B4F6EF107E'
      SOURCE_WINDOWS_PATH = ::File.normalize_path(::File.join(::File.dirname(__FILE__), '..', '..', 'windows'))
      LOCAL_WINDOWS_BIN_PATH = RightScale::RightLinkConfig[:platform].filesystem.ensure_local_drive_path(::File.join(SOURCE_WINDOWS_PATH, 'bin'), TEMP_DIR_NAME)
      CHEF_NODE_CMDLET_DLL_PATH = ::File.normalize_path(::File.join(LOCAL_WINDOWS_BIN_PATH, 'ChefNodeCmdlet.dll')).gsub("/", "\\")

      # Provides a view of the current state objects (instance, chef, ...)
      #
      # == Returns
      # result(Hash):: States:
      #    :cook_state(RightScale::CookState):: current cook state
      #    :chef_state(RightScale::ChefState):: current chef state
      def all_state
        result = {:cook_state => RightScale::CookState, :chef_state => RightScale::ChefState}
      end


      # Formats a command to run the given powershell script.
      #
      # === Parameters
      # script_file_path(String):: powershell script file path
      #
      # == Returns
      # command(String):: command to execute
      def format_command(script_file_path)
        platform = RightScale::RightLinkConfig[:platform]
        shell    = platform.shell

        # import ChefNodeCmdlet.dll to allow powershell scripts to call get-ChefNode, etc.
        lines_before_script = ["import-module #{CHEF_NODE_CMDLET_DLL_PATH}"]

        # enable debug and verbose powershell output if log level allows for it.
        if ::Chef::Log.debug?
          lines_before_script << "$VerbosePreference = 'Continue'"
          lines_before_script << "$DebugPreference = 'Continue'"
        end
        return shell.format_powershell_command4(@new_resource.interpreter, lines_before_script, nil, script_file_path)
      end

    end
  end
end

# self-register
Chef::Platform.platforms[:windows][:default].merge!(:powershell => Chef::Provider::Powershell)
