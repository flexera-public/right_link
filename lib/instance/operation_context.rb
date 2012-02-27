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

module RightScale

  # Context required to run an operation
  # Includes operation input and associated audit
  class OperationContext

    # (Object) Payload associated with operation
    attr_reader :payload

    # (AuditProxy) Associated audit
    attr_reader :audit

    # (TrueClass|FalseClass) Whether bundle succeeded
    attr_accessor :succeeded

    # (TrueClass|FalseClass) Whether bundle is a decommission bundle
    attr_reader :decommission

    # (String) Thread name for context or default
    attr_reader :thread_name

    # Initialize payload and audit
    def initialize(payload, audit, decommission=false)
      @payload = payload
      @audit = audit
      @decommission = decommission
      @thread_name = payload.respond_to?(:thread_name) ? payload.thread_name : ::RightScale::AgentConfig.default_thread_name
    end

  end

end
