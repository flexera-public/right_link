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

require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'actors', 'instance_scheduler'))
require File.normalize_path(File.join(File.dirname(__FILE__), 'audit_proxy_mock'))
require File.normalize_path(File.join(File.dirname(__FILE__), 'instantiation_mock'))

# Since callback and errback take blocks ExecutableSequence cannot be mocked
# easily using pure flexmock so define a mock class explicitely instead
class ExecutableSequenceMock
  attr_reader :context
  attr_reader :pid
  attr_reader :thread_name
  @@last_pid = 100
  def initialize(context, should_fail)
    @context = context
    @thread_name = context.payload.respond_to?(:thread_name) ? context.payload.thread_name : ::RightScale::AgentConfig.default_thread_name
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
  def shutdown
    ::RightScale::SpecHelper::EmTestRunner.stop
  end
end

describe InstanceScheduler do

  include RightScale::SpecHelper

  # stops the bundle queue before stopping EM.
  def stop_bundle_queue_and_em_test
    if @scheduler
      @scheduler.send(:close_bundle_queue) { stop_em_test }
    else
      stop_em_test
    end
  end

  it_should_behave_like 'mocks shutdown request'
  it_should_behave_like 'mocks metadata'

  describe 'schedule bundles' do

    let(:decommission_level) { ::RightScale::ShutdownRequest::TERMINATE }

    # Using this method instead of before(:each) because must be running EM before setup_state is called
    def before_each
      ttl = 4 * 24 * 60 * 60
      setup_state(identity = 'rs-instance-1-1', mock_instance_state = false) do
        @user_id = 42
        @booting_args = ['/state_recorder/record',
                         {:state => "booting", :agent_identity => @identity, :from_state => "pending"},
                         nil,
                         nil,
                         ttl,
                         Proc]
        @operational_args = ['/state_recorder/record',
                             {:state => "operational", :agent_identity => @identity, :from_state => "booting"},
                             nil,
                             nil,
                             ttl,
                             Proc]
        @decommissioning_args = ['/state_recorder/record',
                                 {:state => "decommissioning", :agent_identity => @identity, :from_state => "operational"},
                                 nil,
                                 nil,
                                 ttl,
                                 Proc]
        @decommissioned_args = ['/state_recorder/record',
                                {:state => 'decommissioned', :agent_identity => @identity, :user_id => @user_id,
                                 :skip_db_update => nil, :kind => decommission_level},
                                 Proc]
        @record_success = @results_factory.success_results
        @sender.should_receive(:message_received).and_return(true)
        @sender.should_receive(:send_request).with(*@booting_args).and_yield(@record_success).once.by_default
        @sender.should_receive(:send_request).and_yield(@record_success).by_default
        RightScale::InstanceState.init(@identity)
      end

      @audit = RightScale::AuditProxyMock.new(1)
      @controller = ControllerMock.new
      flexmock(RightScale::AuditProxy).should_receive(:new).and_return(@audit)
      flexmock(RightScale::Platform).should_receive(:controller).and_return(@controller)
      now = Time.at(100000)
      flexmock(Time).should_receive(:now).and_return(now)
      @sender.should_receive(:send_push).with('/registrar/remove', {:agent_identity => @identity,
                                                                    :created_at => now.to_i}).and_return(true)
      @sender.should_receive(:send_request).with(*@operational_args).and_yield(@record_success).once
      RightScale::InstanceState.value = 'operational'
      @bundle = RightScale::InstantiationMock.script_bundle
      @context = RightScale::OperationContext.new(@bundle, @audit)
      @agent = RightScale::Agent.new({:identity => @identity})
      @scheduler = InstanceScheduler.new(@agent)
      @sequence_success = ExecutableSequenceMock.new(@context, should_fail = false)
      @sequence_failure = ExecutableSequenceMock.new(@context, should_fail = true)
      setup_script_execution

      # prevent any actual spawning of cook process.
      flexmock(RightScale::RightPopen).should_receive(:popen3_async).and_return(true)
    end

    after(:each) do
      # not expecting errors.
      ::RightScale::Log.has_errors?.should be_false

      # ensure we have consumed all queued next_ticks instead of leaking them
      queue = EM.instance_variable_get(:@next_tick_queue)
      (queue.nil? || queue.empty?).should be_true
    end

    after(:all) do
      cleanup_state
    end

    it 'should run bundles' do
      run_em_test do
        before_each
        flexmock(RightScale::ExecutableSequenceProxy).should_receive(:new).and_return(@sequence_success)
        @sender.should_receive(:send_request).with(*@decommissioning_args).never
        @sender.should_receive(:send_request).with(*@decommissioned_args).never
        @sender.should_receive(:send_push).with('/registrar/remove', {:agent_identity => @identity}).never
        flexmock(@controller).should_receive(:shutdown).never
        flexmock(@agent).should_receive(:terminate).and_return { stop_bundle_queue_and_em_test }
        res = @scheduler.schedule_bundle(@bundle)
        res.success?.should be_true
        EM.next_tick { @scheduler.terminate }
      end
    end

    it 'should make schedule bundle request' do
      run_em_test do
        before_each
        flexmock(RightScale::ExecutableSequenceProxy).should_receive(:new).and_return(@sequence_success)
        options = {:recipe => true, :recipe_id => 123}
        @sender.should_receive(:send_request).with("/forwarder/schedule_recipe", options.merge(:agent_identity => @identity), Proc).
            and_yield(@record_success).once
        flexmock(@agent).should_receive(:terminate).and_return { stop_bundle_queue_and_em_test }
        res = @scheduler.execute(options)
        res.should be_true
        EM.next_tick { @scheduler.terminate }
      end
    end

    it 'should run bundle returned from schedule request' do
      run_em_test do
        before_each
        flexmock(RightScale::ExecutableSequenceProxy).should_receive(:new).and_return(@sequence_success)
        options = {:recipe => true, :recipe_id => 123}
        bundle = RightScale::ExecutableBundle.new(nil)
        results = @results_factory.success_results(bundle)
        success = RightScale::OperationResult.success
        flexmock(@scheduler).should_receive(:schedule_bundle).with(bundle).and_return(success).once
        @sender.should_receive(:send_request).with("/forwarder/schedule_recipe", options.merge(:agent_identity => @identity), Proc).
            and_yield(results).once
        flexmock(@agent).should_receive(:terminate).and_return { stop_bundle_queue_and_em_test }
        res = @scheduler.execute(options)
        res.should be_true
        EM.next_tick {  @scheduler.terminate }
      end
    end

    context 'without a decommission level' do
      it 'should *not* transition to decommissioned state nor shutdown after decommissioning from rnac' do
        run_em_test do
          before_each
          flexmock(RightScale::ExecutableSequenceProxy).should_receive(:new).and_return(@sequence_success)
          @sender.should_receive(:send_request).
                  with('/booter/get_decommission_bundle', {:agent_identity => @agent.identity}, Proc).
                  and_yield({ '1' => RightScale::OperationResult.success(@bundle) })
          @sender.should_receive(:send_request).with(*@decommissioning_args).and_yield(@record_success).once
          @sender.should_receive(:send_request).with(*@decommissioned_args).never
          flexmock(@audit).should_receive(:append_error).never
          flexmock(@controller).should_receive(:shutdown).never
          @scheduler.run_decommission { stop_bundle_queue_and_em_test }
        end
      end
    end

    context 'with a decommission level' do
      it 'should decommission' do
        run_em_test do
          before_each
          flexmock(RightScale::ExecutableSequenceProxy).should_receive(:new).and_return(@sequence_success)
          @sender.should_receive(:send_request).with(*@decommissioning_args).and_yield(@record_success).once
          @sender.should_receive(:send_request).with(*@decommissioned_args).and_yield(@record_success).once.and_return { stop_bundle_queue_and_em_test }
          flexmock(@audit).should_receive(:append_error).never
          res = @scheduler.schedule_decommission(:bundle => @bundle, :user_id => @user_id, :kind => decommission_level)
          res.success?.should be_true
        end
      end

      it 'should trigger shutdown even if decommission fails but not update inputs' do
        run_em_test do
          before_each
          flexmock(RightScale::ExecutableSequenceProxy).should_receive(:new).and_return(@sequence_failure)
          @sender.should_receive(:send_request).with(*@decommissioning_args).and_yield(@record_success).once
          @sender.should_receive(:send_request).with(*@decommissioned_args).and_yield(@record_success).once.and_return { stop_bundle_queue_and_em_test }
          flexmock(@audit).should_receive(:update_status).ordered.once.and_return { |s, _| s.should include('Scheduling execution of ') }
          flexmock(@audit).should_receive(:update_status).ordered.once.and_return { |s, _| s.should include('failed: ') }
          res = @scheduler.schedule_decommission(:bundle => @bundle, :user_id => @user_id, :kind => decommission_level)
          res.success?.should be_true
        end
      end

      it 'should not decommission twice' do
        run_em_test do
          before_each
          flexmock(RightScale::ExecutableSequenceProxy).should_receive(:new).and_return(@sequence_success)
          @sender.should_receive(:send_request).with(*@decommissioning_args).and_yield(@record_success).once
          @sender.should_receive(:send_request).with(*@decommissioned_args).and_yield(@record_success).once.and_return { stop_bundle_queue_and_em_test }
          res = @scheduler.schedule_decommission(:bundle => @bundle, :user_id => @user_id, :kind => decommission_level)
          res.success?.should be_true
          /decom/.match(::RightScale::InstanceState.value).should_not == nil
          res = @scheduler.schedule_decommission(:bundle => @bundle, :user_id => @user_id, :kind => decommission_level)
          res.success?.should be_false
        end
      end

      it 'should force transition to decommissioned state after SHUTDOWN_DELAY when decommission hangs' do
        begin
          orig_shutdown_delay = InstanceScheduler::DEFAULT_SHUTDOWN_DELAY
          InstanceScheduler.const_set(:DEFAULT_SHUTDOWN_DELAY, 1)
          run_em_test do
            before_each
            flexmock(RightScale::ExecutableSequenceProxy).should_receive(:new).and_return(@sequence_success)
            @sender.should_receive(:send_request).with(*@decommissioning_args).and_yield(@record_success).once
            @sender.should_receive(:send_request).with(*@decommissioned_args).and_yield(@record_success).once.and_return { stop_bundle_queue_and_em_test }
            flexmock(ExecutableSequenceMock).new_instances.should_receive(:run).and_return { sleep 2 }
            @scheduler.schedule_decommission(:bundle => @bundle, :user_id => @user_id, :kind => decommission_level)
          end
        ensure
          InstanceScheduler.const_set(:DEFAULT_SHUTDOWN_DELAY, orig_shutdown_delay)
        end
      end

      it 'should force shutdown when request to transition to decommissioned state fails' do
        run_em_test do
          before_each
          flexmock(RightScale::ExecutableSequenceProxy).should_receive(:new).and_return(@sequence_success)
          @sender.should_receive(:send_request).with(*@decommissioning_args).and_yield(@record_success).once
          @sender.should_receive(:send_request).with(*@decommissioned_args).
                  and_yield({'1' => RightScale::OperationResult.error('test')}).once
          @sender.should_receive(:send_push).with('/registrar/remove', {:agent_identity => @identity})
          flexmock(@controller).should_receive(:shutdown).once.and_return { stop_bundle_queue_and_em_test }
          @scheduler.schedule_decommission(:bundle => @bundle, :user_id => @user_id, :kind => decommission_level)
        end
      end

    end # with a decommission level
  end  # schedule bundles
end  # InstanceScheduler
