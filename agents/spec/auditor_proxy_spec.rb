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

  before(:each) do
    @proxy = RightScale::AuditorProxy.new(1)
    @mapper_proxy = flexmock('mapper proxy instance')
    flexmock(RightScale::MapperProxy).should_receive(:instance).and_return(@mapper_proxy)
  end

  it 'should log, audit and event errors' do
    flexmock(RightScale::RightLinkLog).should_receive(:error).once.with("*ERROR> ERROR")
    @mapper_proxy.should_receive(:push).once.and_return do |_, options|
      options[:text].should == 'ERROR'
      options[:category].should == RightScale::EventCategories::CATEGORY_ERROR
      EM.stop
    end
    EM.run { @proxy.append_error('ERROR') }
  end

  it 'should log statuses' do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with("*RS> STATUS")
    @mapper_proxy.should_receive(:push).once.and_return { |*_| EM.stop }
    EM.run { @proxy.update_status('STATUS') }
  end

  it 'should revert to default event category when an invalid category is given' do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with("*RS> STATUS")
    @mapper_proxy.should_receive(:push).once.and_return do |_, options|
      options[:text].should == 'STATUS'
      options[:category].should == RightScale::EventCategories::CATEGORY_NOTIFICATION
      EM.stop
    end
    EM.run { @proxy.update_status('STATUS', :category => '__INVALID__') }
  end

  it 'should honor the event category' do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with("*RS> STATUS")
    @mapper_proxy.should_receive(:push).once.and_return do |_, options| 
      options[:text].should == 'STATUS'
      options[:category].should == RightScale::EventCategories::CATEGORY_SECURITY
      EM.stop
    end
    EM.run { @proxy.update_status('STATUS', :category => RightScale::EventCategories::CATEGORY_SECURITY) }
  end

  it 'should log outputs' do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with("OUTPUT").and_return { |*_| EM.stop }
    @mapper_proxy.should_receive(:push).once
    EM.run do
      EM.add_timer(RightScale::AuditorProxy::MAX_AUDIT_DELAY + 1) { EM.stop }
      @proxy.append_output('OUTPUT')
    end
  end

  it 'should log sections' do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.ordered.with("#{ '****' * 20 }")
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.ordered.with("*RS>#{ 'SECTION'.center(72) }****")
    @mapper_proxy.should_receive(:push).once.and_return { |*_| EM.stop }
    EM.run { @proxy.create_new_section('SECTION') }
  end

  it 'should log information' do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with("*RS> INFO")
    @mapper_proxy.should_receive(:push).once.and_return { |*_| EM.stop }
    EM.run { @proxy.append_info('INFO') }
  end

end
