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

require 'right_popen'

module RightScale

  # Bundle sequence proxy, create child process to execute bundle
  # Use right_popen gem to control child process asynchronously
  class ExecutableSequenceProxy

    include EM::Deferrable

    # Wait up to 20 seconds to process pending audits after child process exited
    AUDIT_CLOSE_TIMEOUT = 20

    # (Hash) Inputs patch to be forwarded to core after each converge
    attr_accessor :inputs_patch

    # Associated bundle
    attr_reader :bundle

    # Initialize sequence
    #
    # === Parameter
    # context(RightScale::OperationContext):: Bundle to be run and associated audit
    def initialize(context)
      @context = context
      AuditCookStub.instance.audit_proxy = context.audit
      AuditCookStub.instance.on_close { @audit_closed = true; check_done }
    end

    # Run given executable bundle
    # Asynchronous, set deferrable object's disposition
    #
    # === Return
    # true:: Always return true
    def run
      @succeeded = true
      platform = RightScale::RightLinkConfig[:platform]
      input_text = "#{JSON.dump(@context.payload)}\n"

      # update CookState with the latest instance before launching Cook
      CookState.update(InstanceState)

      # FIX: we have an issue with EM not allowing both sockets and named
      # pipes to share the same file/socket id. sending the input on the
      # command line is a temporary workaround.
      if platform.windows?
        input_path = File.normalize_path(File.join(platform.filesystem.temp_dir, "rs_executable_sequence.txt"))
        File.open(input_path, "w") { |f| f.write(input_text) }
        input_text = nil
        cmd_exe_path = File.normalize_path(ENV['ComSpec']).gsub("/", "\\")
        ruby_exe_path = File.normalize_path(RightLinkConfig[:sandbox_ruby_cmd]).gsub("/", "\\")
        input_path = input_path.gsub("/", "\\")
        cmd = "#{cmd_exe_path} /C type #{input_path} | #{ruby_exe_path} #{cook_path_and_arguments}"
      else
        cmd = "#{RightLinkConfig[:sandbox_ruby_cmd]} #{cook_path_and_arguments}"
      end

      EM.next_tick do
        RightScale.popen3(:command        => cmd,
                          :input          => input_text,
                          :target         => self,
                          :environment    => { OptionsBag::OPTIONS_ENV => ENV[OptionsBag::OPTIONS_ENV] },
                          :stdout_handler => :on_read_stdout,
                          :stderr_handler => :on_read_stderr,
                          :exit_handler   => :on_exit)
      end
    end

    protected

    # Path to 'cook' ruby script
    #
    # === Return
    # path(String):: Path to ruby script used to run Chef
    def cook_path
      return File.join(RightLinkConfig[:right_link_path], 'scripts', 'lib', 'cook.rb')
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
      RightLinkLog.error("Unexpected output from execution: #{data.inspect}")
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
        @audit_close_timeout.cancel if @audit_close_timeout
        if !@exit_status.success?
          report_failure("Chef process failure", "Chef process failed #{SubprocessFormatting.reason(@exit_status)}")
        else
          @context.succeeded = true
          succeed
        end
      elsif @exit_status
        @audit_close_timeout = EM::Timer.new(AUDIT_CLOSE_TIMEOUT) { AuditCookStub.instance.close }
      end
      true
    end

    # Report cook process execution failure
    #
    # === Parameters
    # title(String):: Title used to update audit status
    # msg(String):: Failure message
    #
    # === Return
    # true:: Always return true
    def report_failure(title, msg)
      @context.audit.append_error(title, :category => RightScale::EventCategories::CATEGORY_ERROR)
      @context.audit.append_error(msg)
      @context.succeeded = false
      fail
      true
    end

  end

end
