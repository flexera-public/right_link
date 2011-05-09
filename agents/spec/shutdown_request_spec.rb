#
# Copyright (c) 2011 RightScale Inc
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

describe RightScale::ShutdownRequest do

  it_should_behave_like 'mocks state'

  before(:each) do
    @scheduler = flexmock('instance scheduler')
    ::RightScale::ShutdownRequest.init(@scheduler)
    @shutdown_request = ::RightScale::ShutdownRequest.instance

    @audit_proxy = flexmock('AuditProxy')
    flexmock(::RightScale::AuditProxy).should_receive(:create).and_yield(@audit_proxy)
    @audit_proxy.should_receive(:create_new_section).by_default
    @audit_proxy.should_receive(:append_info).by_default
  end

  it 'should reject invalid shutdown requests' do
    runner = lambda { @shutdown_request.level = 'something else' }
    runner.should raise_exception(::RightScale::ShutdownRequest::InvalidLevel)
  end

  it 'should reject immediately for a continuation state' do
    @shutdown_request.continue?.should be_true
    runner = lambda { @shutdown_request.immediately! }
    runner.should raise_exception(::RightScale::ShutdownRequest::InvalidLevel)
  end

  it 'should escalate shutdown request level' do
    @shutdown_request.continue?.should be_true
    @shutdown_request.level = ::RightScale::ShutdownRequest::REBOOT
    @shutdown_request.level.should == ::RightScale::ShutdownRequest::REBOOT
    @shutdown_request.continue?.should be_false
    @shutdown_request.level = ::RightScale::ShutdownRequest::STOP
    @shutdown_request.level.should == ::RightScale::ShutdownRequest::STOP
    @shutdown_request.continue?.should be_false
    @shutdown_request.level = ::RightScale::ShutdownRequest::TERMINATE
    @shutdown_request.level.should == ::RightScale::ShutdownRequest::TERMINATE
    @shutdown_request.continue?.should be_false
  end

  it 'should not deescalate shutdown request level' do
    @shutdown_request.continue?.should be_true
    @shutdown_request.level = ::RightScale::ShutdownRequest::TERMINATE
    @shutdown_request.level.should == ::RightScale::ShutdownRequest::TERMINATE
    @shutdown_request.continue?.should be_false
    @shutdown_request.level = ::RightScale::ShutdownRequest::STOP
    @shutdown_request.level.should == ::RightScale::ShutdownRequest::TERMINATE
    @shutdown_request.continue?.should be_false
    @shutdown_request.level = ::RightScale::ShutdownRequest::REBOOT
    @shutdown_request.level.should == ::RightScale::ShutdownRequest::TERMINATE
    @shutdown_request.continue?.should be_false
    @shutdown_request.level = ::RightScale::ShutdownRequest::CONTINUE
    @shutdown_request.level.should == ::RightScale::ShutdownRequest::TERMINATE
    @shutdown_request.continue?.should be_false
  end

  it 'should escalate shutdown request immediacy' do
    @shutdown_request.immediately?.should be_false
    @shutdown_request.level = ::RightScale::ShutdownRequest::REBOOT
    @shutdown_request.immediately!
    @shutdown_request.immediately?.should be_true
  end

  it 'should submit shutdown request by scheduling' do
    scheduled = false
    @scheduler.should_receive(:schedule_shutdown).and_return { scheduled = true }
    @shutdown_request.continue?.should be_true

    ::RightScale::ShutdownRequest.submit(:kind => ::RightScale::ShutdownRequest::STOP)
    scheduled.should be_true
    @shutdown_request.level.should == ::RightScale::ShutdownRequest::STOP
    @shutdown_request.immediately?.should be_false

    scheduled = false
    ::RightScale::ShutdownRequest.submit(:level => ::RightScale::ShutdownRequest::TERMINATE, :immediately => true)
    scheduled.should be_true
    @shutdown_request.level.should == ::RightScale::ShutdownRequest::TERMINATE
    @shutdown_request.immediately?.should be_true
  end

  it 'should process the continue state by yielding' do
    processed = false
    @shutdown_request.continue?.should be_true
    @shutdown_request.process { processed = true }
    processed.should be_true
  end

  it 'should process reboot request by requesting decommission' do
    processed = false
    sent_request = false
    @mapper_proxy.
      should_receive(:send_persistent_request).
      with("/forwarder/shutdown", {:kind => ::RightScale::ShutdownRequest::REBOOT, :agent_identity => @identity}, Proc).
      and_yield(@results_factory.success_results).
      and_return { sent_request = true }

    @shutdown_request.level = ::RightScale::ShutdownRequest::REBOOT
    @shutdown_request.process { processed = true }
    sent_request.should be_true
    processed.should be_true
  end

end
