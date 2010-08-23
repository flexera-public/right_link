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

require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'agents', 'lib', 'instance', 'audit_proxy'))

module RightScale

  class AuditProxyMock < AuditProxy

    attr_accessor :audits
  
    def initialize(audit_id)
      super(audit_id)
      @audits = []
    end

    # Override raw audit to accumulate audits
    # === Parameters
    # options[:kind](Symbol):: One of :update_status, :new_section, :append_info, :append_error, :output
    # options[:text](String):: Text to be audited
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    #
    # === Return
    # true:: Always return true
    def send_audit(options)
      a = { :audit_id => @audit_id, :request => options[:kind], :text => options[:text] }
      @audits << a
    end

  end
end
