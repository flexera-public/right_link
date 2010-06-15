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

describe RightScale::AuditorProxy do

  PROXY_TIMEOUT = 5

  before(:each) do
    @proxy = RightScale::AuditorProxy.instance
    @forwarder = flexmock(RightScale::RequestForwarder.instance)
  end

  it 'should log, audit and event errors' do
    flexmock(RightScale::RightLinkLog).should_receive(:error).once.with("*ERROR> ERROR")
    @forwarder.should_receive(:push).once.and_return do |_, options|
      options[:text].should == 'ERROR'
      options[:category].should == RightScale::EventCategories::NONE
      EM.stop
    end
    EM.run { @proxy.append_error('ERROR'); EM.add_timer(PROXY_TIMEOUT) { EM.stop; raise 'timeout' } }
  end

  it 'should log statuses' do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with("*RS> STATUS")
    @forwarder.should_receive(:push).once.and_return { |*_| EM.stop }
    EM.run { @proxy.update_status('STATUS'); EM.add_timer(PROXY_TIMEOUT) { EM.stop; raise 'timeout' } }
  end

  it 'should revert to default event category when an invalid category is given' do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with("*RS> STATUS")
    @forwarder.should_receive(:push).once.and_return do |_, options|
      options[:text].should == 'STATUS'
      options[:category].should == RightScale::EventCategories::CATEGORY_NOTIFICATION
      EM.stop
    end
    EM.run { @proxy.update_status('STATUS', :category => '__INVALID__'); EM.add_timer(PROXY_TIMEOUT) { EM.stop; raise 'timeout' } }
  end

  it 'should honor the event category' do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with("*RS> STATUS")
    @forwarder.should_receive(:push).once.and_return do |_, options|
      options[:text].should == 'STATUS'
      options[:category].should == RightScale::EventCategories::CATEGORY_SECURITY
      EM.stop
    end
    EM.run { @proxy.update_status('STATUS', :category => RightScale::EventCategories::CATEGORY_SECURITY); EM.add_timer(PROXY_TIMEOUT) { EM.stop; raise 'timeout' } }
  end

  it 'should log outputs' do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with("OUTPUT").and_return { |*_| EM.stop }
    @forwarder.should_receive(:push).once
    EM.run do
      EM.add_timer(RightScale::AuditorProxy::MAX_AUDIT_DELAY + 1) { EM.stop }
      @proxy.append_output('OUTPUT', :audit_id => 1)
    end
  end

  it 'should log sections' do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.ordered.with("#{ '****' * 20 }")
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.ordered.with("*RS>#{ 'SECTION'.center(72) }****")
    @forwarder.should_receive(:push).once.and_return { |*_| EM.stop }
    EM.run { @proxy.create_new_section('SECTION'); EM.add_timer(PROXY_TIMEOUT) { EM.stop; raise 'timeout' } }
  end

  it 'should log information' do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with("*RS> INFO")
    @forwarder.should_receive(:push).once.and_return { |*_| EM.stop }
    EM.run { @proxy.append_info('INFO'); EM.add_timer(PROXY_TIMEOUT) { EM.stop; raise 'timeout' } }
  end

  it 'should not send audits with persistence' do
    flexmock(RightScale::RightLinkLog).should_receive(:error).once.with("*ERROR> ERROR")
    @forwarder.should_receive(:push).once.and_return do |_, _, opts|
      opts[:persistent].should == false
      EM.stop
    end
    EM.run { @proxy.append_error('ERROR'); EM.add_timer(PROXY_TIMEOUT) { EM.stop; raise 'timeout' } }
  end

end
