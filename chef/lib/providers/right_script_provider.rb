#
# Copyright (c) 2009 RightScale Inc
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

# To install the chef gem:
# sudo gem sources -a http://gems.opscode.com
# sudo gem install chef ohai

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

      # Actually run RightScript
      # Rely on RightScale::popen3 to spawn process and receive both standard and error outputs.
      # Synchronize with EM thread so that execution is synchronous even though RightScale::popen3 is asynchronous.
      #
      # === Return
      # true:: Always return true
      #
      # === Raise
      # RightScale::Exceptions::Exec:: Invalid process exit status
      def action_run
        nickname        = @new_resource.name
        run_started_at  = Time.now
        platform        = RightScale::RightLinkConfig[:platform]

        # 1. Setup audit and environment
        begin
          meta_data = ::File.join(RightScale::RightLinkConfig[:cloud_state_dir], 'meta-data.rb')
          #metadata does not exist on all clouds, hence the conditional
          load(meta_data) if ::File.exist?(meta_data)
        rescue Exception => e
          ::Chef::Log.info("Could not load cloud metadata; script will execute without metadata in environment!")
          RightScale::RightLinkLog.error("#{e.class.name}: #{e.message}, #{e.backtrace[0]}")
        end
        begin
          user_data = ::File.join(RightScale::RightLinkConfig[:cloud_state_dir], 'user-data.rb')
          #user-data should always exist
          load(user_data)
        rescue Exception => e
          ::Chef::Log.info("Could not load user data; script will execute without user data in environment!")
          RightScale::RightLinkLog.error("#{e.class.name}: #{e.message}, #{e.backtrace[0]}")
        end
        @new_resource.parameters.each { |key, val| ENV[key] = val }
        ENV['ATTACH_DIR'] = ENV['RS_ATTACH_DIR'] = @new_resource.cache_dir
        ENV['RS_REBOOT']  = RightScale::InstanceState.past_scripts.include?(nickname) ? 'true' : nil
        # RightScripts expect to find RS_DISTRO or RS_DIST in the environment; provide it for them.
        # Massage the distro name into the format they expect (all lower case, one word, no release info).
        if platform.linux?
          distro = platform.linux.distro.downcase 
          ENV['RS_DISTRO'] = distro
          ENV['RS_DIST']   = distro
        end

        # 2. Fork and wait
        # Bit of a hack here just so we can create a new audit section each time a RightScript is run
        audit_id = Chef::Log.logger[0].auditor.audit_id rescue nil
        if audit_id
          options = { :text => "RightScript: '#{nickname}'", :audit_id => audit_id }
          RightScale::RequestForwarder.push("/auditor/create_new_section", options)
        end
        status = run_script_file(@new_resource.source_file)
        duration = Time.now - run_started_at
        # Security paranoia: wipe inputs from env so next script can't see them
        @new_resource.parameters.each { |key, val| ENV[key] = nil }

        # 3. Handle process exit status
        if status
          ::Chef::Log.info("Script exit status: #{status.exitstatus}")
        else
          ::Chef::Log.info("Script exit status: UNKNOWN; presumed success")
        end
        ::Chef::Log.info("Script duration: #{duration}")

        if !status || status.success?
          RightScale::InstanceState.record_script_execution(nickname)
          @new_resource.updated = true
        else
          raise RightScale::Exceptions::Exec, "RightScript < #{nickname} > returned #{status.exitstatus}"
        end
    
        true
      end

      protected

      # Runs the given RightScript.
      #
      # === Parameters
      # script_file_path(String):: script file path
      #
      # == Returns
      # result(Status):: result of running script
      def run_script_file(script_file_path)
        platform = RightScale::RightLinkConfig[:platform]
        shell    = platform.shell
        command  = shell.format_shell_command(script_file_path)

        return execute(command)
      end

    end

  end

end
