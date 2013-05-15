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

    # @return [Object] payload associated with operation
    attr_reader :payload

    # @return [RightScale::AuditProxy] audit for execution
    attr_reader :audit

    # @return [TrueClass|FalseClass] true if bundle succeeded
    attr_accessor :succeeded

    # @return [TrueClass|FalseClass] true if a decommission bundle
    def decommission?; @decommission; end

    # @return [String] thread name for context or default thread name
    attr_reader :thread_name

    # @param [Object] payload of any kind (but usually executable bundle)
    # @param [RightScale::AuditProxy] audit for execution
    # @param [TrueClass|FalseClass] decommission flag that is true if a decommission bundle or false for boot/operational bundles
    def initialize(payload, audit, decommission=false)
      @payload = payload
      @audit = audit
      @decommission = !!decommission
      @thread_name = payload.respond_to?(:runlist_policy) && payload.runlist_policy ? payload.runlist_policy.thread_name : ::RightScale::AgentConfig.default_thread_name
    end

  end

end
