#
# Copyright (c) 2009-2011 RightScale Inc
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

require 'right_popen'

module RightScale

  # Bundle sequence proxy, create child process to execute bundle
  # Use right_popen gem to control child process asynchronously
  class ExecutableSequenceProxy
    DEFAULT_OPTIONS = {
      :tag_query_timeout => 120
    }

    include EM::Deferrable

    # Wait up to 20 seconds to process pending audits after child process exited
    AUDIT_CLOSE_TIMEOUT = 20

    # (Hash) Inputs patch to be forwarded to core after each converge
    attr_accessor :inputs_patch

    # (::RightScale::OperationContext) operation context containing bundle
    attr_reader :context

    # PID for created process or nil
    attr_reader :pid

    # Execution thread name or default.
    attr_reader :thread_name

    # Initialize sequence
    #
    # === Parameters
    # context(RightScale::OperationContext):: Bundle to be run and associated audit
    #
    # === Options
    # :pid_callback(Proc):: proc that will be called, passing self, when the PID of the child process becomes known
    # :tag_query_timeout(Proc):: default 120 -- how many seconds to wait for the agent tag query to complete, before giving up and continuing
    def initialize(context, options = {})
      options = DEFAULT_OPTIONS.merge(options)
      @context = context
      @thread_name = get_thread_name_from_context(context)
      @pid_callback = options[:pid_callback]
      @tag_query_timeout = options[:tag_query_timeout]

      AuditCookStub.instance.setup_audit_forwarding(@thread_name, context.audit)
      AuditCookStub.instance.on_close(@thread_name) { @audit_closed = true; check_done }
    end
    
    # FIX: thread_name should never be nil from the core in future, but
    # temporarily we must supply the default thread_name before if nil. in
    # future we should fail execution when thread_name is reliably present and
    # for any reason does not match ::RightScale::AgentConfig.valid_thread_name
    # see also ExecutableSequenceProxy#initialize
    #
    # === Parameters
    # bundle(OperationalContext):: An operational context
    #
    # === Return
    # result(String):: Thread name of this context
    def get_thread_name_from_context(context) 
      thread_name = nil
      thread_name = context.thread_name if context.respond_to?(:thread_name)
      Log.warn("Encountered a nil thread name unexpectedly, defaulting to '#{RightScale::AgentConfig.default_thread_name}'") unless thread_name
      thread_name ||= RightScale::AgentConfig.default_thread_name
      unless thread_name =~ RightScale::AgentConfig.valid_thread_name
        raise ArgumentError, "Invalid thread name #{thread_name.inspect}"
      end
      thread_name
    end

    # Run given executable bundle
    # Asynchronous, set deferrable object's disposition
    #
    # === Return
    # true:: Always return true
    def run
      @succeeded = true

      @context.audit.create_new_section('Querying tags')

      # update CookState with the latest instance before launching Cook
      RightScale::AgentTagManager.instance.tags(:timeout=>@tag_query_timeout) do |tags|
        if tags.is_a?(String)
          # AgentTagManager could give us a String (error message)
          Log.error("Failed to query tags before running executable sequence: #{tags}")

          @context.audit.append_error('Could not discover tags due to an error or timeout.')
        else
          # or, it could give us anything else -- generally an array) -- which indicates success
          CookState.update(InstanceState, :startup_tags=>tags)

          if tags.empty?
            @context.audit.append_info('No tags discovered.')
          else
            @context.audit.append_info("Tags discovered: '#{tags.join("', '")}'")
          end
        end

        input_text = "#{MessageEncoder.for_agent(InstanceState.identity).encode(@context.payload)}\n"

        # TEAL FIX: we have an issue with the Windows EM implementation not
        # allowing both sockets and named pipes to share the same file/socket
        # id. sending the input on the command line is a temporary workaround.
        platform = RightScale::Platform
        if platform.windows?
          input_path = File.normalize_path(File.join(platform.filesystem.temp_dir, "rs_executable_sequence#{@thread_name}.txt"))
          File.open(input_path, "w") { |f| f.write(input_text) }
          input_text = nil
          cmd_exe_path = File.normalize_path(ENV['ComSpec']).gsub("/", "\\")
          ruby_exe_path = File.normalize_path(AgentConfig.ruby_cmd).gsub("/", "\\")
          input_path = input_path.gsub("/", "\\")
          cmd = "#{cmd_exe_path} /C type \"#{input_path}\" | #{ruby_exe_path} #{cook_path_and_arguments}"
        else
          # WARNING - always ensure cmd is a String, never an Array of command parts.
          #
          # right_popen handles single-String arguments using "sh -c #{cmd}" which ensures
          # we are invoked through a shell which will parse shell config files and ensure that
          # changes to system PATH, etc are freshened on every converge.
          #
          # If we pass cmd as an Array, right_popen uses the Array form of exec without an
          # intermediate shell, and system config changes will not be picked up.
          cmd = "#{AgentConfig.ruby_cmd} #{cook_path_and_arguments}"
        end

        EM.next_tick do
          # prepare env vars for child process.
          environment = {
            ::RightScale::OptionsBag::OPTIONS_ENV =>
              ::ENV[::RightScale::OptionsBag::OPTIONS_ENV]
          }
          if @context.decommission?
            environment['RS_DECOM_REASON'] = @context.decommission_type
          end

          # spawn
          RightScale::RightPopen.popen3_async(
            cmd,
            :input          => input_text,
            :target         => self,
            :environment    => environment,
            :stdout_handler => :on_read_stdout,
            :stderr_handler => :on_read_stderr,
            :pid_handler    => :on_pid,
            :exit_handler   => :on_exit)
        end
      end
    end

    protected

    # Path to 'cook_runner' ruby script
    #
    # === Return
    # path(String):: Path to ruby script used to run Chef
    def cook_path
      relative_path = File.join(File.dirname(__FILE__), '..', '..', 'bin', 'cook_runner')
      return File.normalize_path(relative_path)
    end

    # Command line fragment for the cook script path and any arguments.
    #
    # === Return
    # path_and_arguments(String):: Cook path plus any arguments properly quoted.
    def cook_path_and_arguments
      return "\"#{cook_path}\""
    end

    # Handle cook standard output, should not get called
    #
    # === Parameters
    # data(String):: Standard output content
    #
    # === Return
    # true:: Always return true
    def on_read_stdout(data)
      Log.error("Unexpected output from execution: #{data.inspect}")
    end

    # Handle cook error output
    #
    # === Parameters
    # data(String):: Error output content
    #
    # === Return
    # true:: Always return true
    def on_read_stderr(data)
      @context.audit.append_info(data)
    end

    # Receives the pid for the created process.
    def on_pid(pid)
      @pid = pid
      @pid_callback.call(self) if @pid_callback
    end

    # Handle runner process exited event
    #
    # === Parameters
    # status(Process::Status):: Exit status
    #
    # === Return
    # true:: Always return true
    def on_exit(status)
      @exit_status = status
      check_done
    end

    # Check whether child process exited *and* all audits were processed
    # Do not proceed until both these conditions are true
    # If the child process exited start a timer so that if there was a failure
    # and the child process was not able to properly close the auditing we will
    # still proceed and be able to handle other scripts/recipes
    #
    # Note: success and failure reports are handled by the cook process for normal
    # scenarios. We only handle cook process execution failures here.
    #
    # === Return
    # true:: Always return true
    def check_done
      if @exit_status && @audit_closed
        if @audit_close_timeout
          @audit_close_timeout.cancel
          @audit_close_timeout = nil
        end
        if !@exit_status.success?
          RightScale::PolicyManager.fail(@context.payload)
          report_failure("Subprocess #{SubprocessFormatting.reason(@exit_status)}")
        else
          @context.succeeded = true
          RightScale::PolicyManager.success(@context.payload)
          succeed
        end
      elsif @exit_status
        @audit_close_timeout = EM::Timer.new(AUDIT_CLOSE_TIMEOUT) { AuditCookStub.instance.close(@thread_name) }
      end
      true
    end

    # Report cook process execution failure
    #
    # === Parameters
    # title(String):: Title used to update audit status
    # msg(String):: Optional, extended failure message
    #
    # === Return
    # true:: Always return true
    def report_failure(title, msg=nil)
      @context.audit.append_error(title, :category => RightScale::EventCategories::CATEGORY_ERROR)
      @context.audit.append_error(msg) unless msg.nil?
      @context.succeeded = false
      fail
      true
    end

  end

end
