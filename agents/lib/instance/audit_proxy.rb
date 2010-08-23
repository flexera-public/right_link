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
  # Audit requests to audit recipes output are buffered as follows:
  #  * Start a timer after each call to audit output
  #  * Reset the timer if a new call to audit output is made
  #  * Actually send the output audit if the total size exceeds
  #    MAX_AUDIT_SIZE or the timer reaches MAX_AUDIT_DELAY
  #  * Audit of any other kind triggers a request and flushes the buffer
  class AuditProxy

    # Maximum size for accumulated output before sending audit request
    # in characters
    MAX_AUDIT_SIZE = 5 * 1024 # 5 KB

    # Maximum amount of time to wait before sending audit request
    # in seconds
    MAX_AUDIT_DELAY = 2

    # (Fixnum) Underlying audit id
    attr_reader :audit_id

    # Initialize audit from pre-existing id
    # 
    # === Parameters
    # audit_id(Fixnum):: Associated audit id
    def initialize(audit_id)
      @audit_id = audit_id
      @size = 0
      @buffer = ''
    end

    # Create a new audit and calls given block back asynchronously with it
    #
    # === Parameters
    # agent_identity(AgentIdentity):: Agent identity used by core agent to retrieve corresponding account
    # summary(String):: Summary to be used for newly created audit
    #
    # === Return
    # true:: Always return true
    def self.create(agent_identity, summary)
      RequestForwarder.instance.request('/auditor/create_entry', :agent_identity => agent_identity,
                                                                 :summary        => summary,
                                                                 :category       => RightScale::EventCategories::NONE) do |r|
        res = RightScale::OperationResult.from_results(r)
        if res.success?
          audit = new(res.content)
          yield audit
        else
          RightLinkLog.warn("Failed to create new audit entry with summary '#{summary}': #{res.content}, aborting...")
        end
        true
      end
    end

    # Update audit summary
    #
    # === Parameters
    # status(String):: New audit entry status
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    #
    # === Return
    # true:: Always return true
    def update_status(status, options={})
      send_audit(:kind => :status, :text => status, :category => options[:category])
    end

    # Start new audit section
    #
    # === Parameters
    # title(String):: Title of new audit section, will replace audit status as well
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    #
    # === Return
    # true:: Always return true
    def create_new_section(title, options={})
      send_audit(:kind => :new_section, :text => title, :category => options[:category])
    end

    # Append info text to current audit section. A special marker will be prepended to each line of audit to
    # indicate that text is not some output. Text will be line-wrapped.
    #
    # === Parameters
    # text(String):: Informational text to append to audit entry
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    #
    # === Return
    # true:: Always return true
    def append_info(text, options={})
      send_audit(:kind => :info, :text => text, :category => options[:category])
    end

    # Append error message to current audit section. A special marker will be prepended to each line of audit to
    # indicate that error message is not some output. Message will be line-wrapped.
    #
    # === Parameters
    # text(String):: Error text to append to audit entry
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    #
    # === Return
    # true:: Always return true
    def append_error(text, options={})
      send_audit(:kind => :error, :text => text, :category => options[:category])
    end

    # Append output to current audit section
    #
    # === Parameters
    # text(String):: Output to append to audit entry
    #
    # === Return
    # true:: Always return true
    #
    # === Raise
    # ApplicationError:: If audit id is missing from passed-in options
    def append_output(text)
      EM.next_tick do
        @buffer << text
        if @buffer.size > MAX_AUDIT_SIZE
          flush_buffer
        else
          reset_timer
        end
      end
    end

 
    protected

    # Flush output buffer then send audits to core agent and log failures
    #
    # === Parameters
    # options[:kind](Symbol):: One of :update_status, :new_section, :append_info, :append_error, :output
    # options[:text](String):: Text to be audited
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    #
    # === Return
    # true:: Always return true
    def send_audit(options)
      EM.next_tick do
        flush_buffer
        internal_send_audit(options)
      end
    end

    # Actually send audits to core agent and log failures
    #
    # === Parameters
    # options[:kind](Symbol):: One of :status, :new_section, :info, :error, :output
    # options[:text](String):: Text to be audited
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    #
    # === Return
    # true:: Always return true
    def internal_send_audit(options)
      opts = { :audit_id => @audit_id, :category => options[:category], :offset => @size }
      opts[:category] ||= EventCategories::CATEGORY_NOTIFICATION
      unless EventCategories::CATEGORIES.include?(opts[:category])
        RightLinkLog.warn("Invalid category '#{opts[:category]}' for notification '#{options[:text]}', using generic category instead")
        opts[:category] = EventCategories::CATEGORY_NOTIFICATION
      end
      
      audit = AuditFormatter.__send__(options[:kind], options[:text])
      @size += audit[:detail].size

      RequestForwarder.instance.push('/auditor/update_entry', opts.merge(audit))
      true
    end

    # Send any buffered output to auditor
    #
    # === Return
    # Always return true
    def flush_buffer
      @timer.cancel if @timer
      unless @buffer.empty?
        internal_send_audit(:kind => :output, :text => @buffer, :category => EventCategories::NONE)
        @buffer = ''
      end
    end

    # Set or reset timer for buffer flush
    #
    # === Return
    # true:: Always return true
    def reset_timer
      # note we are using a single PeriodicTimer because we were running out of
      # one-shot timers with verbose script output. calling cancel on a one-shot
      # timer sends a message but does not immediately remove the timer from EM
      # which maxes out at 1000 one-shot timers.
      @timer = EventMachine::PeriodicTimer.new(MAX_AUDIT_DELAY) { flush_buffer } unless @timer
    end

  end
end

