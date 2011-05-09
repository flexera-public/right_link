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

describe RightScale::ShutdownRequestProxy do

  before(:each) do
    @mock_command_client = flexmock('command client')
    ::RightScale::ShutdownRequestProxy.init(@mock_command_client)
  end

  it 'should query fresh shutdown request state for each reference to proxy instance' do
    sent_request = nil
    flexmock(@mock_command_client).
      should_receive(:send_command).
      with({:name => :get_shutdown_request}, Proc).
      and_yield(:level => ::RightScale::ShutdownRequest::REBOOT, :immediately => true).
      and_return { sent_request = true }

    2.times do
      sent_request = false
      shutdown_request = ::RightScale::ShutdownRequestProxy.instance
      shutdown_request.level.should == ::RightScale::ShutdownRequest::REBOOT
      shutdown_request.immediately?.should be_true
      sent_request.should be_true
    end
  end

  it 'should send shutdown request state for each proxy submit' do
    sent_request = nil
    flexmock(@mock_command_client).
      should_receive(:send_command).
      with({:name => :set_shutdown_request, :level => ::RightScale::ShutdownRequest::REBOOT, :immediately => true}, Proc).
      and_yield(:level => ::RightScale::ShutdownRequest::REBOOT, :immediately => true).
      and_return { sent_request = true }

    2.times do
      sent_request = false
      shutdown_request = ::RightScale::ShutdownRequestProxy.submit(:level => ::RightScale::ShutdownRequest::REBOOT, :immediately => true)
      shutdown_request.level.should == ::RightScale::ShutdownRequest::REBOOT
      shutdown_request.immediately?.should be_true
      sent_request.should be_true
    end
  end

end
