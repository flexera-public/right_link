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
    @proxy = RightScale::AuditProxy.new(@audit_id)
    @forwarder = flexmock(RightScale::RequestForwarder.instance)
    flexmock(EM).should_receive(:next_tick).and_yield
  end

  it 'should send info audits' do
    opts = { :category => RightScale::EventCategories::CATEGORY_NOTIFICATION, :audit_id => @audit_id, :offset => 0 }
    opts.merge!(RightScale::AuditFormatter.info('INFO'))
    @forwarder.should_receive(:push).once.with('/auditor/update_entry', opts)
    @proxy.append_info('INFO')
  end

  it 'should send error audits' do
    opts = { :category => RightScale::EventCategories::CATEGORY_NOTIFICATION, :audit_id => @audit_id, :offset => 0 }
    opts.merge!(RightScale::AuditFormatter.error('ERROR'))
    @forwarder.should_receive(:push).once.with('/auditor/update_entry', opts)
    @proxy.append_error('ERROR')
  end

  it 'should send status audits' do
    opts = { :category => RightScale::EventCategories::CATEGORY_NOTIFICATION, :audit_id => @audit_id, :offset => 0 }
    opts.merge!(RightScale::AuditFormatter.status('STATUS'))
    @forwarder.should_receive(:push).once.with('/auditor/update_entry', opts)
    @proxy.update_status('STATUS')
  end

  it 'should send new section audits' do
    opts = { :category => RightScale::EventCategories::CATEGORY_NOTIFICATION, :audit_id => @audit_id, :offset => 0 }
    opts.merge!(RightScale::AuditFormatter.new_section('NEW SECTION'))
    @forwarder.should_receive(:push).once.with('/auditor/update_entry', opts)
    @proxy.create_new_section('NEW SECTION')
  end

  it 'should send output audits' do
    flexmock(EventMachine::PeriodicTimer).should_receive(:new).and_yield.once
    opts = { :category => RightScale::EventCategories::NONE, :audit_id => @audit_id, :offset => 0 }
    opts.merge!(RightScale::AuditFormatter.output('OUTPUT'))
    @forwarder.should_receive(:push).once.with('/auditor/update_entry', opts)
    @proxy.append_output('OUTPUT')
  end

  it 'should revert to default event category when an invalid category is given' do
    opts = { :category => RightScale::EventCategories::CATEGORY_NOTIFICATION, :audit_id => @audit_id, :offset => 0 }
    opts.merge!(RightScale::AuditFormatter.info('INFO'))
    @forwarder.should_receive(:push).once.with('/auditor/update_entry', opts)
    @proxy.append_info('INFO', :category => '__INVALID__')
  end

  it 'should honor the event category' do
    opts = { :category => RightScale::EventCategories::CATEGORY_SECURITY, :audit_id => @audit_id, :offset => 0 }
    opts.merge!(RightScale::AuditFormatter.info('INFO'))
    @forwarder.should_receive(:push).once.with('/auditor/update_entry', opts)
    @proxy.append_info('INFO', :category => RightScale::EventCategories::CATEGORY_SECURITY)
  end

  it 'should not buffer outputs that exceed the MAX_AUDIT_SIZE' do
    flexmock(EventMachine::PeriodicTimer).should_receive(:new).never
    old_size = RightScale::AuditProxy::MAX_AUDIT_SIZE
    begin
      RightScale::AuditProxy.const_set(:MAX_AUDIT_SIZE, 0)
      opts = { :category => RightScale::EventCategories::NONE, :audit_id => @audit_id, :offset => 0 }
      opts.merge!(RightScale::AuditFormatter.output('OUTPUT'))
      @forwarder.should_receive(:push).once.with('/auditor/update_entry', opts)
      @proxy.append_output('OUTPUT')
    ensure
      RightScale::AuditProxy.const_set(:MAX_AUDIT_SIZE, old_size)
    end
  end

end

