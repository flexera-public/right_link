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
    @thread_count = 4
    @auditors = []
    @auditor_options = []
    @text = 'some text'
    @thread_names = []
    @forwarded_options = {}
    @thread_count.times do |thread_index|
      thread_name = (0 == thread_index) ? ::RightScale::ExecutableBundle::DEFAULT_THREAD_NAME : "thread ##{thread_index}"
      auditor = flexmock("auditor for #{thread_name}")
      @auditors << auditor
      RightScale::AuditCookStub.instance.setup_audit_forwarding(thread_name, auditor)
      @thread_names << thread_name
    end
  end

  it 'should forward info' do
    @thread_count.times do |thread_index|
      auditor = @auditors[thread_index]
      thread_name = @thread_names[thread_index]
      auditor.should_receive(:append_info).with(@text, options).once
      RightScale::AuditCookStub.instance.forward_audit(:append_info, @text, thread_name, @forwarded_options)
    end
  end

  it 'should forward new section' do
    @thread_count.times do |thread_index|
      auditor = @auditors[thread_index]
      thread_name = @thread_names[thread_index]
      auditor.should_receive(:create_new_section).with(@text, options).once
      RightScale::AuditCookStub.instance.forward_audit(:create_new_section, @text, thread_name, options)
    end
  end

  it 'should forward error' do
    @thread_count.times do |thread_index|
      auditor = @auditors[thread_index]
      thread_name = @thread_names[thread_index]
      auditor.should_receive(:append_error).with(@text, options).once
      RightScale::AuditCookStub.instance.forward_audit(:append_error, @text, thread_name, options)
    end
  end

  it 'should forward status' do
    @thread_count.times do |thread_index|
      auditor = @auditors[thread_index]
      thread_name = @thread_names[thread_index]
      auditor.should_receive(:update_status).with(@text, options).once
      RightScale::AuditCookStub.instance.forward_audit(:update_status, @text, thread_name, options)
    end
  end

  it 'should forward output' do
    @thread_count.times do |thread_index|
      auditor = @auditors[thread_index]
      thread_name = @thread_names[thread_index]
      auditor.should_receive(:append_output).with(@text).once
      RightScale::AuditCookStub.instance.forward_audit(:append_output, @text, thread_name, options)
    end
  end

end  # RightScale::AuditCookStub
