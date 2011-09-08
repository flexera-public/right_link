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

require File.join(File.dirname(__FILE__), 'spec_helper')
require File.join(File.dirname(__FILE__), '..', '..', 'actors', 'instance_scheduler')
require File.join(File.dirname(__FILE__), 'audit_proxy_mock')
require File.join(File.dirname(__FILE__), 'instantiation_mock')

# Since callback and errback take blocks ExecutableSequence cannot be mocked
# easily using pure flexmock so define a mock class explicitely instead
class ExecutableSequenceMock
  attr_reader :context
  attr_reader :pid
  attr_reader :thread_name
  @@last_pid = 100
  def initialize(context, should_fail)
    @context = context
    @thread_name = context.payload.respond_to?(:thread_name) ? context.payload.thread_name : ::RightScale::ExecutableBundle::DEFAULT_THREAD_NAME
    @should_fail = should_fail
    @pid = @@last_pid += 4
  end
  def callback(&cb); @callback = cb; end
  def errback(&eb); @errback = eb; end
  def run; @should_fail ? @errback.call : @callback.call; end
  def inputs_patch; true; end
  def failure_title; 'failure title'; end
  def failure_message; 'failure message'; end
end

class ControllerMock
  def shutdown; EM.stop; end
end

describe InstanceScheduler do

  include RightScale::SpecHelper

  describe 'schedule bundles' do

    before(:each) do
      setup_state do
        @user_id = 42
        @identity = "rs-instance-1-1"
        @booting_args = ['/state_recorder/record',
                         {:state => "booting", :agent_identity => @identity, :from_state => "pending"},
                         Proc]
        @operational_args = ['/state_recorder/record',
                             {:state => "operational", :agent_identity => @identity, :from_state => "booting"},
                             Proc]
        @decommissioning_args = ['/state_recorder/record',
                                 {:state => "decommissioning", :agent_identity => @identity, :from_state => "operational"},
                                 Proc]
        @decommissioned_args = ['/state_recorder/record',
                                {:state => 'decommissioned', :agent_identity => @identity, :user_id => @user_id,
                                 :skip_db_update => nil, :kind => 'terminate'},
                                 Proc]
        @record_success = @results_factory.success_results
        @sender.should_receive(:message_received).and_return(true)
        @sender.should_receive(:send_retryable_request).with(*@booting_args).and_yield(@record_success).once.by_default
        @sender.should_receive(:send_retryable_request).and_yield(@record_success).by_default
      end

      # Reset previous calls to EM.next_tick
      EM.instance_variable_set(:@next_tick_queue, [])

      @audit = RightScale::AuditProxyMock.new(1)
      @controller = ControllerMock.new
      flexmock(RightScale::AuditProxy).should_receive(:new).and_return(@audit)
      flexmock(RightScale::Platform).should_receive(:controller).and_return(@controller)
      now = Time.at(100000)
      flexmock(Time).should_receive(:now).and_return(now)
      @sender.should_receive(:send_push).with('/registrar/remove', {:agent_identity => @identity,
                                                                    :created_at => now.to_i}).and_return(true)
      @sender.should_receive(:send_retryable_request).with(*@operational_args).and_yield(@record_success).once
      RightScale::InstanceState.value = 'operational'
      @bundle = RightScale::InstantiationMock.script_bundle
      @context = RightScale::OperationContext.new(@bundle, @audit)
      @agent = RightScale::Agent.new({:identity => @identity})
      @scheduler = InstanceScheduler.new(@agent)
      @sequence_success = ExecutableSequenceMock.new(@context, should_fail = false)
      @sequence_failure = ExecutableSequenceMock.new(@context, should_fail = true)
      setup_script_execution
    end

    after(:all) do
      cleanup_state
    end

    it 'should run bundles' do
      res = @scheduler.schedule_bundle(@bundle)
      res.success?.should be_true
    end

    it 'should decommission' do
      flexmock(RightScale::ExecutableSequenceProxy).should_receive(:new).and_return(@sequence_success)
      @sender.should_receive(:send_retryable_request).with(*@decommissioning_args).and_yield(@record_success).once
      @sender.should_receive(:send_retryable_request).with(*@decommissioned_args).and_yield(@record_success).once.and_return { EM.stop }
      flexmock(@audit).should_receive(:append_error).never
      EM.run do
        res = @scheduler.schedule_decommission(:bundle => @bundle, :user_id => @user_id, :kind => 'terminate')
        res.success?.should be_true
        EM.add_timer(5) { EM.stop; raise 'timeout' }
      end
    end

    it 'should trigger shutdown even if decommission fails but not update inputs' do
      flexmock(RightScale::ExecutableSequenceProxy).should_receive(:new).and_return(@sequence_failure)
      @sender.should_receive(:send_retryable_request).with(*@decommissioning_args).and_yield(@record_success).once
      @sender.should_receive(:send_retryable_request).with(*@decommissioned_args).and_yield(@record_success).once.and_return { EM.stop }
      flexmock(@audit).should_receive(:update_status).ordered.once.and_return { |s, _| s.should include('Scheduling execution of ') }
      flexmock(@audit).should_receive(:update_status).ordered.once.and_return { |s, _| s.should include('failed: ') }
      EM.run do
        res = @scheduler.schedule_decommission(:bundle => @bundle, :user_id => @user_id, :kind => 'terminate')
        res.success?.should be_true
        EM.add_timer(5) { EM.stop; raise 'timeout' }
      end
    end

    it 'should not decommission twice' do
      @sender.should_receive(:send_retryable_request).with(*@decommissioning_args).and_yield(@record_success).once
      EM.run do
        res = @scheduler.schedule_decommission(:bundle => @bundle, :user_id => @user_id, :kind => 'terminate')
        res.success?.should be_true
        res = @scheduler.schedule_decommission(:bundle => @bundle, :user_id => @user_id, :kind => 'terminate')
        res.success?.should be_false
        EM.stop
      end
    end

    it 'should *not* transition to decommissioned state nor shutdown after decommissioning from rnac' do
      flexmock(RightScale::ExecutableSequenceProxy).should_receive(:new).and_return(@sequence_success)
      @sender.should_receive(:send_retryable_request).
              with('/booter/get_decommission_bundle', {:agent_identity => @agent.identity}, Proc).
              and_yield({ '1' => RightScale::OperationResult.success(@bundle) })
      @sender.should_receive(:send_retryable_request).with(*@decommissioning_args).and_yield(@record_success).once
      @sender.should_receive(:send_retryable_request).with(*@decommissioned_args).never
      flexmock(@audit).should_receive(:append_error).never
      flexmock(@controller).should_receive(:shutdown).never
      EM.run do
        @scheduler.run_decommission { EM.stop }
        EM.add_timer(5) { EM.stop; raise 'timeout' }
      end
    end

    it 'should force transition to decommissioned state after SHUTDOWN_DELAY when decommission hangs' do
      flexmock(RightScale::ExecutableSequenceProxy).should_receive(:new).and_return(@sequence_success)
      @sender.should_receive(:send_retryable_request).with(*@decommissioning_args).and_yield(@record_success).once
      @sender.should_receive(:send_retryable_request).with(*@decommissioned_args).and_yield(@record_success).once.and_return { EM.stop }
      begin
        orig_shutdown_delay = InstanceScheduler::SHUTDOWN_DELAY
        InstanceScheduler.const_set(:SHUTDOWN_DELAY, 1)
        flexmock(ExecutableSequenceMock).new_instances.should_receive(:run).and_return { sleep 2 }
        EM.run do
          @scheduler.schedule_decommission(:bundle => @bundle, :user_id => @user_id, :kind => 'terminate')
          EM.add_timer(5) { EM.stop; raise 'timeout' }
        end
      ensure
        InstanceScheduler.const_set(:SHUTDOWN_DELAY, orig_shutdown_delay)
      end
    end

    it 'should force shutdown when request to transition to decommissioned state fails' do
      flexmock(RightScale::ExecutableSequenceProxy).should_receive(:new).and_return(@sequence_success)
      @sender.should_receive(:send_retryable_request).with(*@decommissioning_args).and_yield(@record_success).once
      @sender.should_receive(:send_retryable_request).with(*@decommissioned_args).
              and_yield({'1' => RightScale::OperationResult.error('test')}).once
      @sender.should_receive(:send_push).with('/registrar/remove', {:agent_identity => @identity})
      flexmock(@controller).should_receive(:shutdown).once.and_return { EM.stop }
      EM.run do
        @scheduler.schedule_decommission(:bundle => @bundle, :user_id => @user_id, :kind => 'terminate')
        EM.add_timer(5) { EM.stop; raise 'timeout' }
      end
    end

  end  # schedule bundles

  describe 'thread access' do

    before(:each) do
      @identity = "rs-instance-1-1"
      @agent = RightScale::Agent.new({:identity => @identity})
      @bundles_queue = flexmock('bundles_queue')
      @bundles_queue.should_receive(:activate).and_return { EM.stop; true }
      flexmock(::InstanceScheduler).should_receive(:create_bundles_queue).once.and_return(@bundles_queue)
      flexmock(::RightScale::InstanceState).should_receive(:observe).and_return { EM.stop; true }
      @scheduler = InstanceScheduler.new(@agent)
    end

    it 'should allow only default thread access while booting' do
      flexmock(::RightScale::InstanceState).should_receive(:value).and_return('booting')
      run_em_test do
        @scheduler.acquire_thread(::RightScale::ExecutableBundle::DEFAULT_THREAD_NAME, 123).should be_true
        lambda { @scheduler.acquire_thread('some thread', 123) }.should raise_exception(ThreadError)
      end
    end

    it 'should allow only default thread access while decommissioning' do
      flexmock(::RightScale::InstanceState).should_receive(:value).and_return('decommissioning')
      run_em_test do
        @scheduler.acquire_thread(::RightScale::ExecutableBundle::DEFAULT_THREAD_NAME, 123).should be_true
        lambda { @scheduler.acquire_thread('some thread', 123) }.should raise_exception(ThreadError)
      end
    end

    it 'should allow concurrent thread access while operational' do
      flexmock(::RightScale::InstanceState).should_receive(:value).and_return('operational')
      @bundles_queue.should_receive(:acquire_thread).twice.and_return(true)
      run_em_test do
        @scheduler.acquire_thread(::RightScale::ExecutableBundle::DEFAULT_THREAD_NAME, 123).should be_true
        @scheduler.acquire_thread('some thread', 234).should be_true
      end
    end

  end  # thread access

end  # InstanceScheduler
