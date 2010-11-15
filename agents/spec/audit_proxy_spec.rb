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

require File.join(File.dirname(__FILE__), 'spec_helper')

describe RightScale::AuditProxy do

  PROXY_TIMEOUT = 5

  before(:each) do
    @audit_id = 1
    @audit_proxy = RightScale::AuditProxy.new(@audit_id)
    @mapper_proxy = flexmock('MapperProxy')
    flexmock(RightScale::MapperProxy).should_receive(:instance).and_return(@mapper_proxy).by_default
    flexmock(EM).should_receive(:next_tick).and_yield
  end

  it 'should send info audits' do
    payload = { :category => RightScale::EventCategories::CATEGORY_NOTIFICATION, :audit_id => @audit_id, :offset => 0 }
    payload.merge!(RightScale::AuditFormatter.info('INFO'))
    @mapper_proxy.should_receive(:persistent_push).once.with('/auditor/update_entry', payload, nil, :offline_queueing => true)
    @audit_proxy.append_info('INFO')
  end

  it 'should send error audits' do
    payload = { :category => RightScale::EventCategories::CATEGORY_NOTIFICATION, :audit_id => @audit_id, :offset => 0 }
    payload.merge!(RightScale::AuditFormatter.error('ERROR'))
    @mapper_proxy.should_receive(:persistent_push).once.with('/auditor/update_entry', payload, nil, :offline_queueing => true)
    @audit_proxy.append_error('ERROR')
  end

  it 'should send status audits' do
    payload = { :category => RightScale::EventCategories::CATEGORY_NOTIFICATION, :audit_id => @audit_id, :offset => 0 }
    payload.merge!(RightScale::AuditFormatter.status('STATUS'))
    @mapper_proxy.should_receive(:persistent_push).once.with('/auditor/update_entry', payload, nil, :offline_queueing => true)
    @audit_proxy.update_status('STATUS')
  end

  it 'should send new section audits' do
    payload = { :category => RightScale::EventCategories::CATEGORY_NOTIFICATION, :audit_id => @audit_id, :offset => 0 }
    payload.merge!(RightScale::AuditFormatter.new_section('NEW SECTION'))
    @mapper_proxy.should_receive(:persistent_push).once.with('/auditor/update_entry', payload, nil, :offline_queueing => true)
    @audit_proxy.create_new_section('NEW SECTION')
  end

  it 'should send output audits' do
    flexmock(EventMachine::PeriodicTimer).should_receive(:new).and_yield.once
    payload = { :category => RightScale::EventCategories::NONE, :audit_id => @audit_id, :offset => 0 }
    payload.merge!(RightScale::AuditFormatter.output('OUTPUT'))
    @mapper_proxy.should_receive(:persistent_push).once.with('/auditor/update_entry', payload, nil, :offline_queueing => true)
    @audit_proxy.append_output('OUTPUT')
  end

  it 'should revert to default event category when an invalid category is given' do
    payload = { :category => RightScale::EventCategories::CATEGORY_NOTIFICATION, :audit_id => @audit_id, :offset => 0 }
    payload.merge!(RightScale::AuditFormatter.info('INFO'))
    @mapper_proxy.should_receive(:persistent_push).once.with('/auditor/update_entry', payload, nil, :offline_queueing => true)
    @audit_proxy.append_info('INFO', :category => '__INVALID__')
  end

  it 'should honor the event category' do
    payload = { :category => RightScale::EventCategories::CATEGORY_SECURITY, :audit_id => @audit_id, :offset => 0 }
    payload.merge!(RightScale::AuditFormatter.info('INFO'))
    @mapper_proxy.should_receive(:persistent_push).once.with('/auditor/update_entry', payload, nil, :offline_queueing => true)
    @audit_proxy.append_info('INFO', :category => RightScale::EventCategories::CATEGORY_SECURITY)
  end

  it 'should not buffer outputs that exceed the MAX_AUDIT_SIZE' do
    flexmock(EventMachine::PeriodicTimer).should_receive(:new).never
    old_size = RightScale::AuditProxy::MAX_AUDIT_SIZE
    begin
      RightScale::AuditProxy.const_set(:MAX_AUDIT_SIZE, 0)
      payload = { :category => RightScale::EventCategories::NONE, :audit_id => @audit_id, :offset => 0 }
      payload.merge!(RightScale::AuditFormatter.output('OUTPUT'))
      @mapper_proxy.should_receive(:persistent_push).once.with('/auditor/update_entry', payload, nil, :offline_queueing => true)
      @audit_proxy.append_output('OUTPUT')
    ensure
      RightScale::AuditProxy.const_set(:MAX_AUDIT_SIZE, old_size)
    end
  end

end

