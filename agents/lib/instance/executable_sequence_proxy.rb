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

    # (Hash) Inputs patch to be forwarded to core after each converge
    attr_accessor :inputs_patch

    # Initialize sequence
    #
    # === Parameter
    # bundle(RightScale::ExecutableBundle):: Bundle to be run
    def initialize(bundle)
      @bundle = bundle
    end

    # Run given executable bundle
    # Asynchronous, set deferrable object's disposition
    #
    # === Return
    # true:: Always return true
    def run
      @succeeded = true
      RightScale.popen3(:command        => "#{RightLinkConfig[:sandbox_ruby_cmd]} #{cook_path}",
                        :input          => "#{JSON.dump(@bundle)}\n",
                        :target         => self,
                        :environment    => { OptionsBag::OPTIONS_ENV => ENV[OptionsBag::OPTIONS_ENV] },
                        :stdout_handler => :on_read_stdout, 
                        :stderr_handler => :on_read_stderr, 
                        :exit_handler   => :on_exit)
    end

    protected

    # Path to 'cook' ruby script
    #
    # === Return
    # path(String):: Path to ruby script used to run Chef
    def cook_path
      path = "\"#{File.join(RightLinkConfig[:right_link_path], 'scripts', 'lib', 'cook.rb')}\""
    end

    # Handle cook standard output, should not get called
    #
    # === Parameters
    # data(String):: Standard output content
    #
    # === Return
    # true:: Always return true
    def on_read_stdout(data)
      RightLinkLog.error("Unexpected output from execution: #{data}")
    end

    # Handle cook error output
    #
    # === Parameters
    # data(String):: Error output content
    #
    # === Return
    # true:: Always return true
    def on_read_stderr(data)
      @error_message ||= ''
      @error_message << data
    end

    # Handle runner process exited event
    # Note: success and failure reports are handled by the cook process for normal
    # scenarios. We only handle cook process execution failures here.
    #
    # === Parameters
    # status(Process::Status):: Exit status
    #
    # === Return
    # true:: Always return true
    def on_exit(status)
      if @error_message
        title, message = @error_message.split("\n", 2)
        report_failure(title, message || title)
      elsif !status.success?
        report_failure("Chef process failure", "Chef process failed with return code #{status.exitstatus}")
      else
        succeed
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
      AuditorProxy.instance.update_status("failed: #{ @bundle.to_s }", :audit_id => @bundle.audit_id)
      AuditorProxy.instance.append_error(title, :category => RightScale::EventCategories::CATEGORY_ERROR, :audit_id => @bundle.audit_id)
      AuditorProxy.instance.append_error(msg, :audit_id => @bundle.audit_id)
      fail
      true
    end

  end

end
