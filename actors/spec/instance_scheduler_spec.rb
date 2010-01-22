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

require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require File.join(File.dirname(__FILE__), 'auditor_proxy_mock')
require File.join(File.dirname(__FILE__), 'instantiation_mock')
require 'instance_lib'
require 'instance_scheduler'

describe InstanceScheduler do

  include RightScale::SpecHelpers

  before(:all) do
    setup_state
  end

  before(:each) do
    @auditor = RightScale::AuditorProxyMock.new
    flexmock(RightScale::AuditorProxy).should_receive(:new).and_return(@auditor)
    @bundle = RightScale::InstantiationMock.script_bundle
    @scheduler = InstanceScheduler.new(RightScale::Agent.new({}))
    @sequence_mock = flexmock('ExecutableSequence')
    @sequence_mock.should_receive(:run).and_return(true)
    flexmock(RightScale::ExecutableSequence).should_receive(:new).and_return(@sequence_mock)
  end

  after(:all) do
    cleanup_state
  end

  it 'should run bundles' do
    res = @scheduler.schedule_bundle(@bundle)
    res.success?.should be_true
  end

  it 'should decommission' do
    flexmock(RightScale::RequestForwarder).should_receive(:request).with("/state_recorder/record",
       { :state=>"decommissioning", :agent_identity=>"1" }, Proc)
    res = @scheduler.schedule_decommission(@bundle)
    res.success?.should be_true
  end

  it 'should not decommission twice' do
    flexmock(RightScale::RequestForwarder).should_receive(:request).with("/state_recorder/record",
       { :state=>"decommissioning", :agent_identity=>"1" }, Proc)
    res = @scheduler.schedule_decommission(@bundle)
    res.success?.should be_true
    res = @scheduler.schedule_decommission(@bundle)
    res.success?.should be_false
  end

end
