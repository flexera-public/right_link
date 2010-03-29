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
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'windows', 'chef_node_server'))

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
        current_state    = instance_state

        # 1. Write script source into file, if necessary.
        if script_file_path
          (raise RightScale::Exceptions::Exec, "Missing script file \"#{script_file_path}\"") unless ::File.file?(script_file_path)
        else
          FileUtils.mkdir_p(SCRIPT_TEMP_DIR_PATH)
          script_file_path = ::File.join(SCRIPT_TEMP_DIR_PATH, "powershell_provider_source.ps1")
          ::File.open(script_file_path, "w") { |f| f.write(source) }
        end

        # create ChefNodeServer for powershell scripts to get/set node values.
        #
        # FIX: should be managed at a higher level and be started/stopped once
        # per convergence.
        chef_node_server = ::RightScale::Windows::ChefNodeServer.new(:node => @node, :verbose => false)

        begin
          # 2. Setup environment.
          environment = {} if environment.nil?
          environment['RS_REBOOT'] = current_state.past_scripts.include?(nickname) ? '1' : nil
          @new_resource.environment(environment)

          # 3. execute and wait
          chef_node_server.start
          command = format_command(script_file_path)
          @new_resource.command(command)
          ::Chef::Log.info("Running \"#{nickname}\"")
          super

          # super provider raises an exception on failure, so record success at
          # this point.
          current_state.record_script_execution(nickname)
          @new_resource.updated = true
        ensure
          (FileUtils.rm_rf(SCRIPT_TEMP_DIR_PATH) rescue nil) if ::File.directory?(SCRIPT_TEMP_DIR_PATH)
          chef_node_server.stop rescue nil
        end

        true
      end

      protected

      # Resolves a loadable location for the ChefNodeCmdlet.dll
      def self.locate_chef_node_cmdlet
        cmdlet_path = ::File.expand_path(::File.join(::File.dirname(__FILE__), '..', '..', 'windows', 'bin', 'ChefNodeCmdlet.dll')).gsub("/", "\\")

        # handle case of running spec tests from a network drive by copying .dll
        # to the system drive. Powershell silently fails to load modules from
        # network drives, so the .dll needs to be copied locally ro tun. the
        # .dll location will be the HOMEDRIVE in release use cases or on the
        # build/test machine so this is only meant for VM images running tests
        # from a shared drive.
        homedrive = ENV['HOMEDRIVE']
        if homedrive && homedrive.upcase != cmdlet_path[0,2].upcase
          temp_dir = ::File.expand_path(::File.join(RightScale::RightLinkConfig[:platform].filesystem.temp_dir, 'powershell_provider-B6169A26-91B5-4e3e-93AD-F0B4F6EF107E'))
          FileUtils.rm_rf(temp_dir) if ::File.directory?(temp_dir)
          FileUtils.mkdir_p(temp_dir)
          FileUtils.cp_r(::File.join(::File.dirname(cmdlet_path), '.'), temp_dir)
          cmdlet_path = ::File.join(temp_dir, ::File.basename(cmdlet_path))
        end

        return RightScale::RightLinkConfig[:platform].filesystem.long_path_to_short_path(cmdlet_path)
      end

      CHEF_NODE_CMDLET_DLL_PATH = locate_chef_node_cmdlet

      def instance_state
        RightScale::InstanceState
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

        return shell.format_powershell_command4(@new_resource.interpreter, lines_before_script, nil, script_file_path)
      end

    end
  end
end

# self-register
Chef::Platform.platforms[:windows][:default].merge!(:powershell => Chef::Provider::Powershell)
