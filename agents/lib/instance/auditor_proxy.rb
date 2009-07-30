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
  class AuditorProxy

    # <Integer> Associated audit it
    attr_accessor :audit_id

    # Initialize auditor proxy with given audit id
    #
    # === Parameters
    # audit_id<Integer>:: ID of audit entry that should be appended to
    def initialize(audit_id)
      @audit_id = audit_id
    end

    # Update audit summary
    #
    # === Parameters
    # status<String>:: New audit entry status
    #
    # === Return
    # true:: Always return true
    def update_status(status)
      send_request('update_status', status)
    end

    # Start new audit section
    #
    # === Parameters
    # title<String>:: Title of new audit section, will replace audit status as well
    #
    # === Return
    # true:: Always return true
    def create_new_section(title)
      send_request('create_new_section', title)
    end

    # Append output to current audit section
    #
    # === Parameters
    # text<String>:: Output to append to audit entry, a newline character will be appended to the end
    #
    # === Return
    # true:: Always return true
    def append_output(text)
      send_request('append_output', text)
    end

    # Append raw output to current audit section (does not automatically
    # add a line return to allow for arbitrary output chunks)
    #
    # === Parameters
    # text<String>:: Output to append to audit entry
    #
    # === Return
    # true:: Always return true
    def append_raw_output(text)
      send_request('append_raw_output', text)
    end

    # Append info text to current audit section. A special marker will be prepended to each line of audit to
    # indicate that text is not some output. Text will be line-wrapped.
    #
    # === Parameters
    # text<String>:: Informational text to append to audit entry
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
    # text<String>:: Error text to append to audit entry
    #
    # === Return
    # true:: Always return true
    def append_error(text)
      send_request('append_error', text)
    end

    protected

    # Send audits to core agent and log failures
    #
    # === Parameters
    # request<String>:: Request that should be sent to auditor actor
    # text<String>:: Text to be audited
    #
    # === Return
    # true:: Always return true
    def send_request(request, text)
      log_method = request == 'append_error' ? :error : :info
      log_text = AuditFormatter.send(format_method(request), text)[:detail]
      RightLinkLog.__send__(log_method, "AUDIT #{log_text}")
      a = { :audit_id => @audit_id, :text => text }
      Nanite::MapperProxy.instance.request("/auditor/#{request}", a) do |r|
        status = OperationResult.from_results(r)
        unless status.success?
          msg = "Failed to send audit #{request} #{a.inspect}"
          msg += ": #{status.content}" if status.content
          RightLinkLog.warn msg
        end
      end
      true
    end

    # Audit formatter method to call to format message sent through +request+
    #
    # === Parameters
    # request<String>:: Request used to audit text
    #
    # === Return
    # method<Symbol>:: Corresponding audit formatter method
    def format_method(request)
      method = case request
        when 'update_status'      then :status
        when 'create_new_section' then :new_section
        when 'append_output'      then :output
        when 'append_raw_output'  then :raw_output
        when 'append_info'        then :info
        when 'append_error'       then :error
      end
    end

  end
end