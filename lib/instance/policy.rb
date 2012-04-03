#
# Copyright (c) 2009-2012 RightScale Inc
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

  class Policy
    attr_accessor :policy_name, :audit_period, :audit, :count, :audit_timestamp
    
    def initialize(policy_name, audit_period, audit)
      @policy_name = policy_name.to_s
      @audit_period = audit_period.to_i
      @audit = RightScale::PolicyAudit.new(audit)
      @count = 0
      @audit_timestamp = Time.now

      @audit.audit.append_info("First run of Reconvergence Policy '#{policy_name}' at #{Time.at(@audit_timestamp).to_s}")
    end

    def success
      @count += 1
      timestamp = Time.now
      if timestamp - @audit_timestamp >= @audit_period
        @audit.audit.append_info("Reconvergence Policy '#{@policy_name}' has run successfully #{@count} time#{@count > 1 ? 's' : ''} since #{Time.at(@audit_timestamp).to_s}")
        @audit_timestamp = timestamp
        @count = 0
      end
    end

    def fail
      @count = 0
    end
  end
  
end