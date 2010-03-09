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
require File.join(File.dirname(__FILE__), '..', 'lib', 'instance_scheduler')
require File.join(File.dirname(__FILE__), 'auditor_proxy_mock')
require File.join(File.dirname(__FILE__), 'instantiation_mock')

# Since callback and errback take blocks ExecutableSequence cannot be mocked
# easily using pure flexmock so define a mock class explicitely instead
class ExecutableSequenceMock
  def initialize(should_fail); @should_fail = should_fail; end
  def callback(&cb); @callback = cb; end
  def errback(&eb); @errback = eb; end
  def run; @should_fail ? @errback.call : @callback.call; end
  def inputs_patch; true; end
end

class ControllerMock
  def shutdown; EM.stop; end
end

describe InstanceScheduler do

  include RightScale::SpecHelpers

  before(:all) do
    setup_state
  end

  before(:each) do
    # Reset previous calls to EM.next_tick and EM.defer
    EM.instance_variable_set(:@threadqueue, [])
    EM.instance_variable_set(:@next_tick_queue, nil)
    
    @auditor = RightScale::AuditorProxyMock.new
    @controller = ControllerMock.new
    flexmock(RightScale::AuditorProxy).should_receive(:new).and_return(@auditor)
    flexmock(RightScale::RequestForwarder).should_receive(:push).with('/registrar/remove', Hash).and_return(true)
    flexmock(RightScale::Platform).should_receive(:controller).and_return(@controller)
    flexmock(RightScale::RequestForwarder).should_receive(:request).with("/state_recorder/record", { :state=>"decommissioning", :agent_identity=>"1" }, Proc)
    @bundle = RightScale::InstantiationMock.script_bundle
    @scheduler = InstanceScheduler.new(RightScale::Agent.new({}))
    @success_sequence = ExecutableSequenceMock.new(should_fail=false)
    @failure_sequence = ExecutableSequenceMock.new(should_fail=true)
  end

  after(:all) do
    cleanup_state
  end

  it 'should run bundles' do
    res = @scheduler.schedule_bundle(@bundle)
    res.success?.should be_true
  end

  it 'should decommission' do
    flexmock(RightScale::ExecutableSequence).should_receive(:new).and_return(@success_sequence)
    flexmock(RightScale::RequestForwarder).should_receive(:push).with('/updater/update_inputs', Hash).once.and_return(true)
    flexmock(@auditor).should_receive(:append_error).never
    EM.run do
      res = @scheduler.schedule_decommission(@bundle)
      res.success?.should be_true
      EM.add_timer(5) { EM.stop; raise 'timeout' }
    end
  end

  it 'should not update inputs on failures' do
    flexmock(RightScale::ExecutableSequence).should_receive(:new).and_return(@failure_sequence)
    flexmock(RightScale::RequestForwarder).should_receive(:push).with('/updater/update_inputs', Hash).never
    flexmock(@auditor).should_receive(:append_error).never
    EM.run do
      res = @scheduler.schedule_decommission(@bundle)
      res.success?.should be_true
      EM.add_timer(5) { EM.stop; raise 'timeout' }
    end
  end

  it 'should not decommission twice' do
    flexmock(RightScale::RequestForwarder).should_receive(:request).with("/state_recorder/record",
       { :state=>"decommissioning", :agent_identity=>"1" }, Proc)
    res = @scheduler.schedule_decommission(@bundle)
    res.success?.should be_true
    res = @scheduler.schedule_decommission(@bundle)
    res.success?.should be_false
  end

  it 'should *not* shutdown after decommissioning from rnac' do
    flexmock(RightScale::ExecutableSequence).should_receive(:new).and_return(@success_sequence)
    flexmock(RightScale::RequestForwarder).should_receive(:push).with('/updater/update_inputs', Hash).once.and_return(true)
    flexmock(RightScale::RequestForwarder).should_receive(:request).with('/booter/get_decommission_bundle', Hash, Proc).and_yield({ '1' => RightScale::OperationResult.success(@bundle) })
    flexmock(@auditor).should_receive(:append_error).never
    flexmock(@controller).should_receive(:shutdown).never
    EM.run do
      @scheduler.run_decommission { EM.stop }
      EM.add_timer(5) { EM.stop; raise 'timeout' }
    end
  end

  it 'should force shutdown after SHUTDOWN_DELAY when decommission hangs' do
    flexmock(RightScale::ExecutableSequence).should_receive(:new).and_return(@success_sequence)
    flexmock(RightScale::RequestForwarder).should_receive(:request).with("/state_recorder/record", Hash, Proc)
    flexmock(@controller).should_receive(:shutdown).once.and_return  { EM.stop }
    begin
      orig_shutdown_delay = InstanceScheduler::SHUTDOWN_DELAY
      InstanceScheduler.const_set(:SHUTDOWN_DELAY, 1)
      flexmock(ExecutableSequenceMock).new_instances.should_receive(:run).and_return { sleep 2 }
      RightScale::InstanceState.value = 'operational'
      EM.run do
        @scheduler.schedule_decommission(@bundle)
        EM.add_timer(2) { EM.stop; raise 'timeout' }
      end
    ensure
      InstanceScheduler.const_set(:SHUTDOWN_DELAY, orig_shutdown_delay)
    end
  end

end
