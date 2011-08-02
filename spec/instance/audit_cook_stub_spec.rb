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
#
require File.join(File.dirname(__FILE__), 'spec_helper')

describe RightScale::AuditCookStub do

  before(:each) do
    @audit_proxy = flexmock('audit_proxy')
    RightScale::AuditCookStub.instance.audit_proxy = @audit_proxy
    @text = 'some text'
    @options = { :one => 'two' }
  end

  it 'should forward info' do
    @audit_proxy.should_receive(:append_info).with(@text, @options).once
    RightScale::AuditCookStub.instance.forward_audit(:append_info, @text, @options)
  end

  it 'should forward new section' do
    @audit_proxy.should_receive(:create_new_section).with(@text, @options).once
    RightScale::AuditCookStub.instance.forward_audit(:create_new_section, @text, @options)
  end

  it 'should forward error' do
    @audit_proxy.should_receive(:append_error).with(@text, @options).once
    RightScale::AuditCookStub.instance.forward_audit(:append_error, @text, @options)
  end

  it 'should forward status' do
    @audit_proxy.should_receive(:update_status).with(@text, @options).once
    RightScale::AuditCookStub.instance.forward_audit(:update_status, @text, @options)
  end

  it 'should forward output' do
    @audit_proxy.should_receive(:append_output).with(@text)
    RightScale::AuditCookStub.instance.forward_audit(:append_output, @text, @options)
  end

end

