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

require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))

describe RightScale::AuditProxy do

  PROXY_TIMEOUT = 5

  before(:each) do
    @audit_id = 1
    @type = '/auditor/update_entry'
    @payload = {:category => RightScale::EventCategories::CATEGORY_NOTIFICATION, :audit_id => @audit_id, :offset => 0}
    @options = {:timeout => 7200}
    @audit_proxy = RightScale::AuditProxy.new(@audit_id)
    @retryable_request = flexmock("retryable request", :callback => true, :errback => true).by_default
    @retryable_request.should_receive(:run).once.by_default
    flexmock(RightScale::RetryableRequest).should_receive(:new).with(@type, @payload, @options).and_return(@retryable_request).once.by_default
    flexmock(EM).should_receive(:next_tick).and_yield
  end

  it 'should send info audits' do
    @payload.merge!(RightScale::AuditFormatter.info('INFO'))
    @audit_proxy.append_info('INFO').should be true
  end

  it 'should clean audits of malformed characters' do
    bad_text = "Hello \x90\x9D"
    bad_text.force_encoding("ASCII-8BIT")
    bad_text_corrected = "Hello ??"
    @payload.merge!(RightScale::AuditFormatter.info(bad_text_corrected))
    @audit_proxy.append_info(bad_text).should be true
  end if "".respond_to?(:encoding)

  it 'should send error audits' do
    @payload.merge!(RightScale::AuditFormatter.error('ERROR'))
    @audit_proxy.append_error('ERROR')
  end

  it 'should send status audits' do
    @payload.merge!(RightScale::AuditFormatter.status('STATUS'))
    @audit_proxy.update_status('STATUS')
  end

  it 'should send new section audits' do
    @payload.merge!(RightScale::AuditFormatter.new_section('NEW SECTION'))
    @audit_proxy.create_new_section('NEW SECTION')
  end

  it 'should send output audits' do
    flexmock(EventMachine::PeriodicTimer).should_receive(:new).and_yield.once
    @payload.merge!(:category => RightScale::EventCategories::NONE)
    @payload.merge!(RightScale::AuditFormatter.output('OUTPUT'))
    @audit_proxy.append_output('OUTPUT')
  end

  it 'should revert to default event category when an invalid category is given' do
    @payload.merge!(RightScale::AuditFormatter.info('INFO'))
    @audit_proxy.append_info('INFO', :category => '__INVALID__')
  end

  it 'should honor the event category' do
    @payload.merge!(:category => RightScale::EventCategories::CATEGORY_SECURITY)
    @payload.merge!(RightScale::AuditFormatter.info('INFO'))
    @audit_proxy.append_info('INFO', :category => RightScale::EventCategories::CATEGORY_SECURITY)
  end

  it 'should not buffer outputs that exceed the MAX_AUDIT_SIZE' do
    flexmock(EventMachine::PeriodicTimer).should_receive(:new).never
    old_size = RightScale::AuditProxy::MAX_AUDIT_SIZE
    begin
      RightScale::AuditProxy.const_set(:MAX_AUDIT_SIZE, 0)
      @payload.merge!(:category => RightScale::EventCategories::NONE)
      @payload.merge!(RightScale::AuditFormatter.output('OUTPUT'))
      @audit_proxy.append_output('OUTPUT')
    ensure
      RightScale::AuditProxy.const_set(:MAX_AUDIT_SIZE, old_size)
    end
  end

  it 'should log error if audit update request fails' do
    flexmock(RightScale::Log).should_receive(:error).with("Failed to send update for audit 1 (timed out)").once
    @retryable_request.should_receive(:errback).and_yield("timed out").once
    @payload.merge!(RightScale::AuditFormatter.info('INFO'))
    @audit_proxy.append_info('INFO')
  end

  it 'should log error if audit update request setup fails' do
    flexmock(RightScale::Log).should_receive(:error).with("Failed to send update for audit 1", RuntimeError, :trace).once
    @retryable_request.should_receive(:run).and_raise(RuntimeError)
    @payload.merge!(RightScale::AuditFormatter.info('INFO'))
    @audit_proxy.append_info('INFO')
  end
end

