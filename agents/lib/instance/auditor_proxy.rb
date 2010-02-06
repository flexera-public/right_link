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

module RightScale

  # Provides access to core agents audit operation through helper methods
  # that take care of formatting the audits appropriately
  # Audit requests are buffered as follows:
  #  * Start a timer after each call to audit output
  #  * Reset the timer if a new call to audit output is made
  #  * Actually send the output audit if the total size exceeds
  #    MIN_AUDIT_SIZE or the timer reaches MAX_AUDIT_DELAY
  #  * Audit of any other kind triggers a request and flushes the buffer
  #
  # Note: All methods implementations have to run in the EventMachine
  # thread as they interact with EM constructs
  class AuditorProxy

    # Minimum size for accumulated output before sending audit request
    # in characters
    MIN_AUDIT_SIZE = 5 * 1024 # 5 KB

    # Maximum amount of time to wait before sending audit request
    # in seconds
    MAX_AUDIT_DELAY = 2

    # (Integer) Associated audit it
    attr_accessor :audit_id

    # Initialize auditor proxy with given audit id
    #
    # === Parameters
    # audit_id(Integer):: ID of audit entry that should be appended to
    def initialize(audit_id)
      @audit_id = audit_id
      @buffer = ''
    end

    # Update audit summary
    #
    # === Parameters
    # status(String):: New audit entry status
    #
    # === Return
    # true:: Always return true
    def update_status(status)
      send_request('update_status', status)
    end

    # Start new audit section
    #
    # === Parameters
    # title(String):: Title of new audit section, will replace audit status as well
    #
    # === Return
    # true:: Always return true
    def create_new_section(title)
      send_request('create_new_section', title)
    end

    # Append output to current audit section
    #
    # === Parameters
    # text(String):: Output to append to audit entry
    #
    # === Return
    # true:: Always return true
    def append_output(text)
      EM.next_tick do
        @buffer << text
        if @buffer.size > MIN_AUDIT_SIZE
          flush_buffer
        else
          reset_timer
        end
      end
    end

    # Append info text to current audit section. A special marker will be prepended to each line of audit to
    # indicate that text is not some output. Text will be line-wrapped.
    #
    # === Parameters
    # text(String):: Informational text to append to audit entry
    #
    # === Return
    # true:: Always return true
    def append_info(text)
      send_request('append_info', text)
    end

    # Append error message to current audit section. A special marker will be prepended to each line of audit to
    # indicate that error message is not some output. Message will be line-wrapped.
    #
    # === Parameters
    # text(String):: Error text to append to audit entry
    #
    # === Return
    # true:: Always return true
    def append_error(text)
      send_request('append_error', text)
    end

    protected

    # Flush output buffer then send audits to core agent and log failures
    #
    # === Parameters
    # request(String):: Request that should be sent to auditor actor
    # text(String):: Text to be audited
    #
    # === Return
    # true:: Always return true
    def send_request(request, text)
      EM.next_tick do
        flush_buffer
        internal_send_request(request, text)
      end
    end

    # Actually send audits to core agent and log failures
    #
    # === Parameters
    # request(String):: Request that should be sent to auditor actor
    # text(String):: Text to be audited
    #
    # === Return
    # true:: Always return true
    def internal_send_request(request, text)
      log_method = request == 'append_error' ? :error : :info
      log_text = AuditFormatter.send(format_method(request), text)[:detail]
      RightLinkLog.__send__(log_method, "AUDIT #{log_text.chomp}")
      a = { :audit_id => @audit_id, :text => text }
      RightScale::RequestForwarder.push("/auditor/#{request}", a)
      true
    end

    # Send any buffered output to auditor
    #
    # === Return
    # Always return true
    def flush_buffer
      @timer.cancel if @timer
      unless @buffer.empty?
        internal_send_request('append_output', @buffer)
        @buffer = ''
      end
    end

    # Set or reset timer for buffer flush
    #
    # === Return
    # true:: Always return true
    def reset_timer
      @timer.cancel if @timer
      @timer = EM::Timer.new(MAX_AUDIT_DELAY) { flush_buffer }
    end

    # Audit formatter method to call to format message sent through +request+
    #
    # === Parameters
    # request(String):: Request used to audit text
    #
    # === Return
    # method(Symbol):: Corresponding audit formatter method
    def format_method(request)
      method = case request
        when 'update_status'      then :status
        when 'create_new_section' then :new_section
        when 'append_output'      then :output
        when 'append_info'        then :info
        when 'append_error'       then :error
      end
    end

  end
end
