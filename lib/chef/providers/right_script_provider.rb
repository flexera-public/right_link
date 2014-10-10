#
# Copyright (c) 2009-2012 RightScale Inc
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
require 'right_popen'
require 'chef/mixin/command'

class Chef

  class Provider

    # RightScript chef provider.
    class RightScript < Chef::Provider

      include Chef::Mixin::Command

      # No concept of a 'current' resource for RightScript execution, this is a no-op
      #
      # === Return
      # true:: Always return true
      def load_current_resource
        true
      end

      # runs the RightScript in a child process.
      #
      # === Return
      # true:: Always return true
      #
      # === Raise
      # RightScale::Exceptions::Exec:: Invalid process exit status
      def action_run
        nickname        = @new_resource.name
        display_version = @new_resource.display_version || ''
        run_started_at  = Time.now
        platform        = RightScale::Platform
        current_state   = all_state

        # 1. Setup audit and environment
        begin
          meta_data = ::File.join(RightScale::AgentConfig.cloud_state_dir, 'meta-data-cache.rb')
          #metadata does not exist on all clouds, hence the conditional
          load(meta_data) if ::File.exists?(meta_data)
        rescue Exception => e
          ::Chef::Log.info("Could not load cloud metadata; script will execute without metadata in environment!")
          RightScale::Log.error("Failed loading cloud metadata", e)
        end
        begin
          user_data = ::File.join(RightScale::AgentConfig.cloud_state_dir, 'user-data.rb')
          #user-data should always exist
          load(user_data)
        rescue Exception => e
          ::Chef::Log.info("Could not load user data; script will execute without user data in environment!")
          RightScale::Log.error("Failed loading user data", e)
        end
        @new_resource.parameters.each { |key, val| ENV[key] = val }

        # Provide the customary RightScript environment metadata
        ENV['ATTACH_DIR'] = ENV['RS_ATTACH_DIR'] = @new_resource.cache_dir
        ENV['RS_ALREADY_RUN']                    = current_state[:chef_state].past_scripts.include?(nickname) ? 'true' : nil
        ENV['RS_REBOOT']                         = current_state[:cook_state].reboot? ? 'true' : nil

        # RightScripts expect to find RS_DISTRO, RS_DIST and RS_ARCH in the environment.
        # Massage the distro name into the format they expect (all lower case, one word, no release info).
        if platform.linux?
          distro = platform.flavor.downcase
          ENV['RS_DISTRO'] = distro
          ENV['RS_DIST']   = distro
          arch_info=`uname -i`.downcase + `uname -m`.downcase
          if arch_info =~ /i386/ || arch_info =~ /i686/
              ENV['RS_ARCH'] = "i386"
          elsif arch_info =~ /64/
              ENV['RS_ARCH'] = "x86_64"
          else
              ENV['RS_ARCH'] = "unknown"
          end
        end

        # Add Cloud-Independent Attributes
        if node[:cloud]
          ENV['RS_CLOUD_PROVIDER'] = node[:cloud][:provider]

          # On some clouds (gce) node[:cloud][:public_ipv4] could be array.
          instance_public_ip = Array(node[:cloud][:public_ipv4]).first
          instance_public_ip = (node[:cloud][:public_ips].is_a?(Array) && node[:cloud][:public_ips].first) unless  instance_public_ip
          if instance_public_ip
            ENV['RS_PUBLIC_IP'] = instance_public_ip
          else
            ::Chef::Log.info("Could not retrieve instance public IP")
          end

          # On some clouds (gce) node[:cloud][:public_ipv4] could be array.
          instance_private_ip = Array(node[:cloud][:local_ipv4]).first
          instance_private_ip = (node[:cloud][:private_ips].is_a?(Array) && node[:cloud][:private_ips].first) unless instance_private_ip
          if instance_private_ip
            ENV['RS_PRIVATE_IP'] = instance_private_ip
          else
            ::Chef::Log.info("Could not retrieve instance private IP")
          end

        else
          ::Chef::Log.info("Could not retrieve cloud information")
        end

        # 2. Fork and wait
        # Bit of a hack here just so we can create a new audit section each time a RightScript is run
        name_and_version = display_version.empty? ?
          "'#{nickname}'" :
          "'#{nickname}' #{display_version}"

        Chef::Log.logger.create_new_section("RightScript: #{name_and_version}")

        status = run_script_file(@new_resource.source_file)
        duration = Time.now - run_started_at
        # Security paranoia: wipe inputs from env so next script can't see them
        @new_resource.parameters.each { |key, _| ENV[key] = nil }

        # 3. Handle process exit status
        if status
          ::Chef::Log.info("Script exit status: #{status.exitstatus}")
        else
          ::Chef::Log.info("Script exit status: UNKNOWN; presumed success")
        end
        ::Chef::Log.info("Script duration: #{duration}")

        if !status || status.success?
          current_state[:chef_state].record_script_execution(nickname)
          @new_resource.updated_by_last_action(true)

          # a script may have requested reboot via rs_shutdown command line
          # tool. if the script requested immediate shutdown then we must call
          # exit here to interrupt the Chef converge (assuming any subsequent
          # boot recipes are pending). otherwise, defer shutdown until scripts/
          # recipes finish or another script escalates to an immediate shutdown.
          exit 0 if RightScale::ShutdownRequestProxy.instance.immediately?
        else
          raise RightScale::Exceptions::RightScriptExec,
                "RightScript < #{name_and_version} > #{RightScale::SubprocessFormatting.reason(status)}"
        end

        true
      end

      protected

      # Provides a view of the current state objects (instance, chef, ...)
      #
      # == Returns
      # result(Hash):: States:
      #    :cook_state(RightScale::CookState):: current cook state
      #    :chef_state(RightScale::ChefState):: current chef state
      def all_state
        result = {:cook_state => RightScale::CookState, :chef_state => RightScale::ChefState}
      end

      # Runs the given RightScript.
      #
      # === Parameters
      # script_file_path(String):: script file path
      #
      # == Returns
      # result(Status):: result of running script
      def run_script_file(script_file_path)
        platform = RightScale::Platform
        shell    = platform.shell
        command  = shell.format_shell_command(script_file_path)
        status, stdout, stderr = output_of_command(command, {})

        ::Chef::Log.info(stdout)
        return status
      end

    end

  end

end

# self-register
Chef::Platform.platforms[:default].merge!(:right_script => Chef::Provider::RightScript)
