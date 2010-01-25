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

require 'fileutils'
require 'right_popen'

class Chef

  class Provider

    # Powershell chef provider.
    class Powershell < Chef::Provider

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
        @nickname        = @new_resource.name
        @auditor         = create_auditor_proxy
        @run_started_at  = Time.now
        source           = @new_resource.source
        script_file_path = @new_resource.source_path
        parameters       = @new_resource.parameters
        cache_dir        = @new_resource.cache_dir
        current_state    = instance_state

        # 1. Write script source into file, if necessary.
        if script_file_path
          raise "Missing script file \"#{script_file_path}\"" unless ::File.file?(script_file_path)
          created_script_file = false
        else
          FileUtils.mkdir_p(cache_dir)
          script_file_path = ::File.join(cache_dir, "powershell_provider_source.ps1")
          ::File.open(script_file_path, "w") { |f| f.write(source) }
          created_script_file = true
        end

        begin
          # 2. Setup audit and environment.
          parameters.each { |key, val| ENV[key] = val }
          ENV['RS_ATTACH_DIR'] = cache_dir
          ENV['RS_REBOOT']     = current_state.past_scripts.include?(@nickname) ? '1' : nil

          # 3. Fork and wait
          status = run_script_file(script_file_path)

          # 4. Handle process exit status
          if status
            @auditor.append_info("Script exit status: #{status.exitstatus}")
          else
            @auditor.append_info("Script exit status: UNKNOWN; presumed success")
          end

          @auditor.append_info("Script duration: #{@duration}")

          if !status || status.success?
            current_state.record_script_execution(@nickname)
            @new_resource.updated = true
          else
            raise RightScale::Exceptions::Exec, "Powershell < #{@nickname} > returned #{status.exitstatus}"
          end
        ensure
          # attempt to cleanup temporary script.
          (File.delete(script_file_path) rescue nil) if created_script_file
        end

        true
      end

      protected

      def create_auditor_proxy
        RightScale::AuditorProxy.new(@new_resource.audit_id)
      end

      def instance_state
        RightScale::InstanceState
      end

      # Runs the given powershell script, optionally requiring the 32-bit version
      # of powershell on 64-bit systems.
      #
      # === Parameters
      # script_file_path(String):: powershell script file path
      #
      # == Returns
      # status(String):: result of running script
      def run_script_file(script_file_path)
        platform      = RightScale::RightLinkConfig[:platform]
        shell         = platform.shell
        @mutex        = Mutex.new
        @exited_event = ConditionVariable.new
        @status       = nil
        @mutex.synchronize do
          cmd = shell.format_powershell_command(script_file_path)
          RightScale.popen3(cmd, self, :on_read_stdout, :on_read_stderr, :on_exit)
          @exited_event.wait(@mutex)
        end
        return @status
      end

      # Data available in STDOUT pipe event
      # Audit raw output
      #
      # === Parameters
      # data<String>:: STDOUT data
      #
      # === Return
      # true:: Always return true
      def on_read_stdout(data)
        @auditor.append_output(data)
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
