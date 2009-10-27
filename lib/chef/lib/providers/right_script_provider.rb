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

BASE_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..'))
require File.join(BASE_DIR, 'right_popen', 'lib', 'right_popen')

class Chef

  class Provider

    # RightScript chef provider.
    class RightScript < Chef::Provider

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
        @mutex          = Mutex.new
        @exited_event   = ConditionVariable.new
        @nickname       = @new_resource.name
        @auditor        = RightScale::AuditorProxy.new(@new_resource.audit_id)
        @run_started_at = Time.now
        source          = @new_resource.source
        parameters      = @new_resource.parameters
        cache_dir       = @new_resource.cache_dir

        # 1. Write script source into file
        FileUtils.mkdir_p(cache_dir)
        sc_filename = ::File.join(cache_dir, "script_source")
        ::File.open(sc_filename, "w") { |f| f.write(source) }
        ::File.chmod(0744, sc_filename)

        # 2. Setup audit and environment
        platform = RightScale::Platform.new
        @auditor.create_new_section("Running RightScript < #{@nickname} >")
        begin
          meta_data = ::File.join(RightScale::RightLinkConfig[:cloud_state_dir], 'meta-data.rb')
          #metadata does not exist on all clouds, hence the conditional
          load(meta_data) if ::File.exist?(meta_data)
        rescue Exception => e
          @auditor.append_info("Could not load cloud metadata; script will execute without metadata in environment!")
          RightScale::RightLinkLog.error("#{e.class.name}: #{e.message}, #{e.backtrace[0]}")
        end
        begin
          user_data = ::File.join(RightScale::RightLinkConfig[:cloud_state_dir], 'user-data.rb')
          #user-data should always exist
          load(user_data)
        rescue Exception => e
          @auditor.append_info("Could not load user data; script will execute without user data in environment!")
          RightScale::RightLinkLog.error("#{e.class.name}: #{e.message}, #{e.backtrace[0]}")
        end
        parameters.each { |key, val| ENV[key] = val }
        ENV['ATTACH_DIR'] = ENV['RS_ATTACH_DIR'] = cache_dir
        ENV['RS_REBOOT']  = RightScale::InstanceState.past_scripts.include?(@nickname) ? '1' : nil
        ENV['RS_DISTRO'] = platform.linux.distro if platform.linux?

        # 3. Fork and wait
        @mutex.synchronize do
          cmd = sc_filename.gsub(' ', '\\ ')
          #RightScale.popen25(cmd, self, :on_read_stdout, :on_exit)
          RightScale.popen3(cmd, self, :on_read_stdout, :on_read_stderr, :on_exit)
          @exited_event.wait(@mutex)
        end

        # 4. Handle process exit status
        if @status
          @auditor.append_info("Script exit status: #{@status.exitstatus}")
        else
          @auditor.append_info("Script exit status: UNKNOWN; presumed success")
        end

        @auditor.append_info("Script duration: #{@duration}")

        if !@status || @status.success?
          RightScale::InstanceState.record_script_execution(@nickname)
          @new_resource.updated = true
        else
          raise RightScale::Exceptions::Exec, "RightScript < #{@nickname} > returned #{@status.exitstatus}"
        end
    
        true
      end

      protected

      # Data available in STDOUT pipe event
      # Audit raw output
      #
      # === Parameters
      # data<String>:: STDOUT data
      #
      # === Return
      # true:: Always return true
      def on_read_stdout(data)
        @auditor.append_raw_output(data)
      end

      # Data available in STDERR pipe event
      # Audit error
      #
      # === Parameters
      # data<String>:: STDERR data
      #
      # === Return
      # true:: Always return true
      def on_read_stderr(data)
        @auditor.append_error(data)
      end

      # Process exited event
      # Record duration and process exist status and signal Chef thread so it can resume
      #
      # === Parameters
      # status<Process::Status>:: Process exit status
      #
      # === Return
      # true:: Always return true
      def on_exit(status)
        @mutex.synchronize do
          @duration = Time.now - @run_started_at
          @status = status
          @exited_event.signal
        end
        true
      end

    end

  end

end
