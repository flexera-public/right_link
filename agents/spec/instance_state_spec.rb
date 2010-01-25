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

describe RightScale::InstanceState do

  include RightScale::SpecHelpers
 
  before(:all) do
    flexmock(RightScale::RightLinkLog).should_receive(:debug)
    setup_state
  end

  after(:all) do
    cleanup_state
  end

  it 'should initialize' do
    RightScale::InstanceState.value.should == 'booting'
    RightScale::InstanceState.identity.should == @identity
  end 

  it 'should handle image bundling' do
    flexmock(RightScale::RightLinkLog).should_receive(:debug)
    RightScale::InstanceState.init(@identity)
    flexmock(RightScale::RequestForwarder).should_receive(:request).
            with('/state_recorder/record', { :state => "operational", :agent_identity => "1" }, Proc).
            and_yield(@results_factory.success_results)
    RightScale::InstanceState.value = 'operational'
    flexmock(RightScale::RequestForwarder).should_receive(:request).
            with('/state_recorder/record', { :state => "booting", :agent_identity => "2" }, Proc).
            and_yield(@results_factory.success_results)
    RightScale::InstanceState.init('2')
    RightScale::InstanceState.value.should == 'booting'
  end

  it 'should record script execution' do
    RightScale::InstanceState.past_scripts.should be_empty
    RightScale::InstanceState.record_script_execution('test')
    RightScale::InstanceState.past_scripts.should == [ 'test' ]
  end

  it 'should record startup tags when transitioning from booting' do
    flexmock(RightScale::RequestForwarder).should_receive(:request).
            with('/state_recorder/record', { :state => "booting", :agent_identity => "1" }, Proc).
            and_yield(@results_factory.success_results)
    RightScale::InstanceState.init(@identity)
    flexmock(RightScale::RequestForwarder).should_receive(:request).
            with('/state_recorder/record', { :state => "operational", :agent_identity => "1" }, Proc).
            and_yield(@results_factory.success_results)
    RightScale::InstanceState.startup_tags = [ 'a_tag', 'another_tag' ]
    RightScale::InstanceState.value = 'operational'
    RightScale::InstanceState.startup_tags = nil
    RightScale::InstanceState.init(@identity)
    RightScale::InstanceState.startup_tags.should == [ 'a_tag', 'another_tag' ]
  end

end
