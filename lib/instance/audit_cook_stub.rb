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

require 'singleton'

module RightScale

  # This class acts as a recipient of audit requests sent by the cook
  # process.
  # The audit proxy which will forward the audits to the core should be
  # initialized before each invokation to cook
  class AuditCookStub

    include Singleton

    def initialize
      @auditors = {}
      @close_callbacks = {}
    end

    # Sets up the audit proxy that should be used to forward all audit commands.
    #
    # === Parameters
    # thread_name(String):: execution thread name or default
    # auditor(AuditProxy):: audit proxy
    def setup_audit_forwarding(thread_name, auditor)
      @auditors ||= {}
      @auditors[thread_name] = auditor
    end

    # Forward audit command received from cook using audit proxy
    #
    # === Parameters
    # kind(Symbol):: Kind of audit, one of :append_info, :append_error, :create_new_section, :update_status and :append_output
    # text(String):: Audit content
    # thread_name(String):: thread name for audit or default
    # options[:category]:: Optional, associated event category, one of RightScale::EventCategories
    #
    # === Raise
    # RuntimeError:: If audit_proxy is not set prior to calling this
    def forward_audit(kind, text, thread_name, options)
      auditor = @auditors[thread_name]
      return unless auditor
      if kind == :append_output
        auditor.append_output(text)
      else
        auditor.__send__(kind, text, options)
      end
    end

    # Register listener for when audit proxy is closed/reset
    # Listener is executable sequence proxy to synchronize betweek
    # cook process going away and all audits having been processed
    #
    # === Parameters
    # thread_name(String):: execution thread name or default
    #
    # === Block
    # Given block should not take any argument and gets called back when proxy is reset
    #
    # === Return
    # true:: Always return true
    def on_close(thread_name, &blk)
      @close_callbacks[thread_name] = blk
      true
    end

    # Reset proxy object and notify close event listener
    #
    # === Parameters
    # thread_name(String):: execution thread name or default
    #
    # === Return
    # true:: Always return true
    def close(thread_name)
      close_callback = @close_callbacks[thread_name]
      close_callback.call if close_callback
      true
    ensure
      @auditors[thread_name] = nil
      @close_callbacks[thread_name] = nil
    end

  end

end
