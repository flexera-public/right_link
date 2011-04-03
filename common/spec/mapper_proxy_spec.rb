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
require File.join(File.dirname(__FILE__), '..', '..', 'config', 'platform.rb')

describe RightScale::MapperProxy do

  include FlexMock::ArgumentTypes

  before(:each) do
#   flexmock(RightScale::RightLinkLog).should_receive(:error).with(on { |arg| puts caller.join("\n") } )
    flexmock(RightScale::RightLinkLog).should_receive(:error).never.by_default
    flexmock(RightScale::RightLinkLog).should_receive(:warn).never.by_default
    @timer = flexmock("timer", :cancel => true).by_default
  end

  describe "when fetching the instance" do
    before do
      RightScale::MapperProxy.class_eval do
        if class_variable_defined?(:@@instance)
          remove_class_variable(:@@instance) 
        end
      end
    end
    
    it "should return nil when the instance is undefined" do
      RightScale::MapperProxy.instance.should == nil
    end
    
    it "should return the instance if defined" do
      instance = flexmock
      RightScale::MapperProxy.class_eval do
        @@instance = "instance"
      end
      
      RightScale::MapperProxy.instance.should_not == nil
    end
  end

  describe "when monitoring broker connectivity" do
    before(:each) do
      flexmock(EM).should_receive(:next_tick).and_yield.by_default
      @broker = flexmock("Broker", :subscribe => true, :publish => ["broker"], :connected? => true,
                         :identity_parts => ["host", 123, 0, 0, nil]).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker, :options => {:ping_interval => 0}).by_default
    end

    it "should start inactivity timer at initialization time" do
      @agent.should_receive(:options).and_return(:ping_interval => 1000)
      flexmock(EM::Timer).should_receive(:new).with(1000, Proc).and_return(@timer).once
      RightScale::MapperProxy.new(@agent)
    end

    it "should not start inactivity timer at initialization time if ping disabled" do
      flexmock(EM::Timer).should_receive(:new).never
      RightScale::MapperProxy.new(@agent)
    end

    it "should restart inactivity timer only if sufficient time has elapsed since last restart" do
      @agent.should_receive(:options).and_return(:ping_interval => 1000)
      flexmock(EM::Timer).should_receive(:new).with(1000, Proc).and_return(@timer).once
      instance = RightScale::MapperProxy.new(@agent)
      flexmock(instance).should_receive(:restart_inactivity_timer).once
      instance.message_received
      instance.message_received
    end

    it "should check connectivity if the inactivity timer times out" do
      @agent.should_receive(:options).and_return(:ping_interval => 1000)
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).once.by_default
      RightScale::MapperProxy.new(@agent)
      instance = RightScale::MapperProxy.instance
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).and_yield.once
      flexmock(instance).should_receive(:check_connection).once
      instance.message_received
    end

    it "should ignore messages received if ping disabled" do
      @agent.should_receive(:options).and_return(:ping_interval => 0)
      flexmock(EM::Timer).should_receive(:new).never
      RightScale::MapperProxy.new(@agent)
      RightScale::MapperProxy.instance.message_received
    end

    it "should log an exception if the connectivity check fails" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed connectivity check/, Exception, :trace).once
      @agent.should_receive(:options).and_return(:ping_interval => 1000)
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).once.by_default
      RightScale::MapperProxy.new(@agent)
      instance = RightScale::MapperProxy.instance
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).and_yield.once
      flexmock(instance).should_receive(:check_connection).and_raise(Exception)
      instance.message_received
    end

    it "should attempt to reconnect if mapper ping times out" do
      flexmock(RightScale::RightLinkLog).should_receive(:warn).with(/Mapper ping via broker/).once
      @agent.should_receive(:options).and_return(:ping_interval => 1000)
      broker_id = "rs-broker-localhost-5672"
      @broker.should_receive(:identity_parts).with(broker_id).and_return(["localhost", 5672, 0, 0, nil]).once
      @agent.should_receive(:connect).with("localhost", 5672, 0, 0, true).once
      old_ping_timeout = RightScale::MapperProxy::PING_TIMEOUT
      begin
        RightScale::MapperProxy.const_set(:PING_TIMEOUT, 0.5)
        EM.run do
          EM.add_timer(1) { EM.stop }
          RightScale::MapperProxy.new(@agent)
          instance = RightScale::MapperProxy.instance
          flexmock(instance).should_receive(:publish).with(RightScale::Request, nil).and_return([broker_id])
          instance.__send__(:check_connection)
        end
      ensure
        RightScale::MapperProxy.const_set(:PING_TIMEOUT, old_ping_timeout)
      end
    end
  end
  
  describe "when making a push request" do
    before(:each) do
      @timer = flexmock("timer")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      @broker = flexmock("Broker", :subscribe => true, :publish => true).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker, :options => {}).by_default
      RightScale::MapperProxy.new(@agent)
      @instance = RightScale::MapperProxy.instance
      @instance.initialize_offline_queue
    end

    it "should create a Push object" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |push|
        push.class.should == RightScale::Push
      end, hsh(:persistent => false, :mandatory => true)).once
      @instance.send_push('/welcome/aboard', 'iZac')
    end

    it "should set the correct target if specified" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |push|
        push.target.should == 'my-target'
      end, hsh(:persistent => false, :mandatory => true)).once
      @instance.send_push('/welcome/aboard', 'iZac', 'my-target')
    end

    it "should set the correct target selectors for fanout if specified" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |push|
        push.tags.should == ['tag']
        push.selector.should == :all
        push.scope.should == {:account => 123}
      end, hsh(:persistent => false, :mandatory => true)).once
      @instance.send_push('/welcome/aboard', 'iZac', :tags => ['tag'], :selector => :all, :scope => {:account => 123})
    end

    it "should set correct attributes on the push message" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |push|
        push.type.should == '/welcome/aboard'
        push.token.should_not be_nil
        push.persistent.should be_false
        push.from.should == 'agent'
        push.target.should be_nil
        push.expires_at.should == 0
      end, hsh(:persistent => false, :mandatory => true)).once
      @instance.send_push('/welcome/aboard', 'iZac')
    end

    it 'should queue the push if in offline mode and :offline_queueing specified' do
      @broker.should_receive(:publish).once
      @instance.enable_offline_mode
      @instance.instance_variable_get(:@queueing_mode).should == :offline
      @instance.send_push('/welcome/aboard', 'iZac', nil, :offline_queueing => false)
      @instance.instance_variable_get(:@queue).size.should == 0
      @instance.send_push('/welcome/aboard', 'iZac', nil, :offline_queueing => true)
      @instance.instance_variable_get(:@queue).size.should == 1
    end
  end

  describe "when making a send_persistent_push request" do
    before(:each) do
      @timer = flexmock("timer")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      @broker = flexmock("Broker", :subscribe => true, :publish => true).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker, :options => {}).by_default
      RightScale::MapperProxy.new(@agent)
      @instance = RightScale::MapperProxy.instance
      @instance.initialize_offline_queue
    end

    it "should create a Push object" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |push|
        push.class.should == RightScale::Push
      end, hsh(:persistent => true, :mandatory => true)).once
      @instance.send_persistent_push('/welcome/aboard', 'iZac')
    end

    it "should set correct attributes on the push message" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |push|
        push.type.should == '/welcome/aboard'
        push.token.should_not be_nil
        push.persistent.should be_true
        push.from.should == 'agent'
        push.target.should be_nil
        push.expires_at.should == 0
      end, hsh(:persistent => true, :mandatory => true)).once
      @instance.send_persistent_push('/welcome/aboard', 'iZac')
    end
  end

  describe "when making a send_retryable_request request" do
    before(:each) do
      @timer = flexmock("timer")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).by_default
      flexmock(EM).should_receive(:next_tick).and_yield.by_default
      @broker_id = "broker"
      @broker_ids = [@broker_id]
      @broker = flexmock("Broker", :subscribe => true, :publish => @broker_ids, :connected? => true,
                         :identity_parts => ["host", 123, 0, 0, nil]).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker).by_default
      @agent.should_receive(:options).and_return({:ping_interval => 0, :time_to_live => 100}).by_default
      RightScale::MapperProxy.new(@agent)
      @instance = RightScale::MapperProxy.instance
      @instance.initialize_offline_queue
    end

    it "should create a Request object" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.class.should == RightScale::Request
      end, hsh(:persistent => false, :mandatory => true)).once
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|response|}
    end

    it "should process request in next tick to preserve pending request data integrity" do
      flexmock(EM).should_receive(:next_tick).and_yield.once
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|response|}
    end

    it "should set correct attributes on the request message" do
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000))
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.type.should == '/welcome/aboard'
        request.token.should_not be_nil
        request.persistent.should be_false
        request.from.should == 'agent'
        request.target.should be_nil
        request.expires_at.should == 1000100
      end, hsh(:persistent => false, :mandatory => true)).once
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|response|}
    end

    it "should disable time-to-live if disabled in configuration" do
      @agent.should_receive(:options).and_return({:ping_interval => 0, :time_to_live => 0})
      RightScale::MapperProxy.new(@agent)
      @instance = RightScale::MapperProxy.instance
      @instance.initialize_offline_queue
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000))
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.expires_at.should == 0
      end, hsh(:persistent => false, :mandatory => true)).once
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|response|}
    end

    it "should set the correct target if specified" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.target.should == 'my-target'
      end, hsh(:persistent => false, :mandatory => true)).once
      @instance.send_retryable_request('/welcome/aboard', 'iZac', 'my-target') {|response|}
    end

    it "should set the correct target selectors if specified" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.tags.should == ['tag']
        request.selector.should == :any
        request.scope.should == {:account => 123}
      end, hsh(:persistent => false, :mandatory => true)).once
      @instance.send_retryable_request('/welcome/aboard', 'iZac', :tags => ['tag'], :scope => {:account => 123})
    end

    it "should set up for retrying the request if necessary by default" do
      flexmock(@instance).should_receive(:publish_with_timeout_retry).once
      @instance.send_retryable_request('/welcome/aboard', 'iZac', 'my-target') {|response|}
    end

    it "should store the response handler" do
      response_handler = lambda {}
      flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return('abc').once
      @instance.send_retryable_request('/welcome/aboard', 'iZac', &response_handler)
      @instance.pending_requests['abc'][:response_handler].should == response_handler
    end

    it "should store the request receive time" do
      flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return('abc').once
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
      @instance.request_age.should be_nil
      @instance.send_retryable_request('/welcome/aboard', 'iZac')
      @instance.pending_requests['abc'][:receive_time].should == Time.at(1000000)
      flexmock(Time).should_receive(:now).and_return(Time.at(1000100))
      @instance.request_age.should == 100
    end

    it 'should queue the request if in offline mode and :offline_queueing specified' do
      @broker.should_receive(:publish).once
      @instance.enable_offline_mode
      @instance.instance_variable_get(:@queueing_mode).should == :offline
      @instance.send_retryable_request('/welcome/aboard', 'iZac', nil, :offline_queueing => false)
      @instance.instance_variable_get(:@queue).size.should == 0
      @instance.send_retryable_request('/welcome/aboard', 'iZac', nil, :offline_queueing => true)
      @instance.instance_variable_get(:@queue).size.should == 1
    end

    it "should dump the pending requests" do
      flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return('abc').once
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000))
      @instance.send_retryable_request('/welcome/aboard', 'iZac')
      @instance.dump_requests.should == ["#{Time.at(1000000).localtime} <abc>"]
    end

    describe "with retry" do
      it "should convert value to nil if 0" do
        @instance.__send__(:nil_if_zero, 0).should == nil
      end

      it "should not convert value to nil if not 0" do
        @instance.__send__(:nil_if_zero, 1).should == 1
      end

      it "should leave value as nil if nil" do
        @instance.__send__(:nil_if_zero, nil).should == nil
      end

      it "should not setup for retry if retry_timeout nil" do
        flexmock(EM).should_receive(:add_timer).never
        @agent.should_receive(:options).and_return({:retry_timeout => nil})
        RightScale::MapperProxy.new(@agent)
        @instance = RightScale::MapperProxy.instance
        @broker.should_receive(:publish).once
        @instance.send_retryable_request('/welcome/aboard', 'iZac') {|response|}
      end

      it "should not setup for retry if retry_interval nil" do
        flexmock(EM).should_receive(:add_timer).never
        @agent.should_receive(:options).and_return({:retry_interval => nil})
        RightScale::MapperProxy.new(@agent)
        @instance = RightScale::MapperProxy.instance
        @broker.should_receive(:publish).once
        @instance.send_retryable_request('/welcome/aboard', 'iZac') {|response|}
      end

      it "should not setup for retry if publish failed" do
        flexmock(EM).should_receive(:add_timer).never
        @agent.should_receive(:options).and_return({:retry_timeout => 60, :retry_interval => 60})
        RightScale::MapperProxy.new(@agent)
        @instance = RightScale::MapperProxy.instance
        @broker.should_receive(:publish).and_return([]).once
        @instance.send_retryable_request('/welcome/aboard', 'iZac') {|response|}
      end

      it "should setup for retry if retry_timeout and retry_interval not nil and publish successful" do
        flexmock(EM).should_receive(:add_timer).with(60, any).once
        @agent.should_receive(:options).and_return({:retry_timeout => 60, :retry_interval => 60})
        RightScale::MapperProxy.new(@agent)
        @instance = RightScale::MapperProxy.instance
        @broker.should_receive(:publish).and_return(@broker_ids).once
        @instance.send_retryable_request('/welcome/aboard', 'iZac') {|response|}
      end

      it "should adjust retry interval by recent request duration" do

      end

      it "should succeed after retrying once" do
        EM.run do
          token = 'abc'
          result = RightScale::OperationResult.non_delivery(RightScale::OperationResult::RETRY_TIMEOUT)
          flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return(token).twice
          @agent.should_receive(:options).and_return({:retry_timeout => 0.3, :retry_interval => 0.1})
          RightScale::MapperProxy.new(@agent)
          @instance = RightScale::MapperProxy.instance
          flexmock(@instance).should_receive(:check_connection).once
          @broker.should_receive(:publish).and_return(@broker_ids).twice
          @instance.send_retryable_request('/welcome/aboard', 'iZac') do |response|
            result = RightScale::OperationResult.from_results(response)
          end
          EM.add_timer(0.15) do
            @instance.pending_requests.empty?.should be_false
            @instance.handle_response(RightScale::Result.new(token, nil, {'from' => RightScale::OperationResult.success}, nil))
          end
          EM.add_timer(0.3) do
            EM.stop
            result.success?.should be_true
            @instance.pending_requests.empty?.should be_true
          end
        end
      end

      it "should timeout after retrying twice" do
        pending 'Too difficult to get timing right for Windows' if RightScale::Platform.windows?
        EM.run do
          result = RightScale::OperationResult.success
          flexmock(RightScale::RightLinkLog).should_receive(:warn).once
          @agent.should_receive(:options).and_return({:retry_timeout => 0.6, :retry_interval => 0.1})
          RightScale::MapperProxy.new(@agent)
          @instance = RightScale::MapperProxy.instance
          flexmock(@instance).should_receive(:check_connection).once
          @broker.should_receive(:publish).and_return(@broker_ids).times(3)
          @instance.send_retryable_request('/welcome/aboard', 'iZac') do |response|
            result = RightScale::OperationResult.from_results(response)
          end
          @instance.pending_requests.empty?.should be_false
          EM.add_timer(1) do
            EM.stop
            result.non_delivery?.should be_true
            result.content.should == RightScale::OperationResult::RETRY_TIMEOUT
            @instance.pending_requests.empty?.should be_true
          end
        end
      end

      it "should retry with same request expires_at value" do
        EM.run do
          token = 'abc'
          expires_at = nil
          flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return(token).twice
          @agent.should_receive(:options).and_return({:retry_timeout => 0.5, :retry_interval => 0.1})
          RightScale::MapperProxy.new(@agent)
          @instance = RightScale::MapperProxy.instance
          flexmock(@instance).should_receive(:check_connection).once
          @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
            request.expires_at.should == (expires_at ||= request.expires_at)
          end, hsh(:persistent => false, :mandatory => true)).and_return(@broker_ids).twice
          @instance.send_retryable_request('/welcome/aboard', 'iZac') {|response|}
          EM.add_timer(0.2) { EM.stop }
        end
      end

      describe "and checking connection status" do
        before(:each) do
          @broker_id = "broker"
          @broker_ids = [@broker_id]
        end

        it "should not check connection if check already in progress" do
          flexmock(EM::Timer).should_receive(:new).and_return(@timer).never
          @instance.pending_ping = true
          flexmock(@instance).should_receive(:publish).never
          @instance.__send__(:check_connection, @broker_ids)
        end

        it "should publish ping to mapper" do
          flexmock(EM::Timer).should_receive(:new).and_return(@timer).once
          flexmock(@instance).should_receive(:publish).with(on { |request| request.type.should == "/mapper/ping" },
                                                            @broker_ids).and_return(@broker_ids).once
          @instance.__send__(:check_connection, @broker_id)
          @instance.pending_requests.size.should == 1
        end

        it "should not make any connection changes if receive ping response" do
          flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return('abc').once
          @timer.should_receive(:cancel).once
          flexmock(EM::Timer).should_receive(:new).and_return(@timer).once
          flexmock(@instance).should_receive(:publish).and_return(@broker_ids).once
          @instance.__send__(:check_connection, @broker_id)
          @instance.pending_ping.should == @timer
          @instance.pending_requests.size.should == 1
          @instance.pending_requests['abc'][:response_handler].call(nil)
          @instance.pending_ping.should == nil
        end

        it "should try to reconnect if ping times out" do
          flexmock(RightScale::RightLinkLog).should_receive(:warn).once
          flexmock(EM::Timer).should_receive(:new).and_yield.once
          flexmock(@agent).should_receive(:connect).once
          @instance.__send__(:check_connection, @broker_id)
          @instance.pending_ping.should == nil
        end

        it "should log error if attempt to reconnect fails" do
          flexmock(RightScale::RightLinkLog).should_receive(:warn).once
          flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed to reconnect/, Exception, :trace).once
          flexmock(@agent).should_receive(:connect).and_raise(Exception)
          flexmock(EM::Timer).should_receive(:new).and_yield.once
          @instance.__send__(:check_connection, @broker_id)
        end
      end
    end
  end

  describe "when making a send_persistent_request" do
    before(:each) do
      @timer = flexmock("timer")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).by_default
      flexmock(EM).should_receive(:next_tick).and_yield.by_default
      @broker_id = "broker"
      @broker_ids = [@broker_id]
      @broker = flexmock("Broker", :subscribe => true, :publish => @broker_ids, :connected? => true,
                         :identity_parts => ["host", 123, 0, 0, nil]).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker,
                        :options => {:ping_interval => 0, :time_to_live => 100}).by_default
      RightScale::MapperProxy.new(@agent)
      @instance = RightScale::MapperProxy.instance
      @instance.initialize_offline_queue
    end

    it "should create a Request object" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.class.should == RightScale::Request
      end, hsh(:persistent => true, :mandatory => true)).once
      @instance.send_persistent_request('/welcome/aboard', 'iZac') {|response|}
    end

    it "should set correct attributes on the request message" do
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000))
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.type.should == '/welcome/aboard'
        request.token.should_not be_nil
        request.persistent.should be_true
        request.from.should == 'agent'
        request.target.should be_nil
        request.expires_at.should == 0
      end, hsh(:persistent => true, :mandatory => true)).once
      @instance.send_persistent_request('/welcome/aboard', 'iZac') {|response|}
    end

    it "should set the correct target if specified" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.target.should == 'my-target'
      end, hsh(:persistent => true, :mandatory => true)).once
      @instance.send_persistent_request('/welcome/aboard', 'iZac', 'my-target') {|response|}
    end

    it "should set the correct target selectors if specified" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.tags.should == ['tag']
        request.selector.should == :any
        request.scope.should == {:account => 123}
      end, hsh(:persistent => true, :mandatory => true)).once
      @instance.send_persistent_request('/welcome/aboard', 'iZac', :tags => ['tag'], :scope => {:account => 123})
    end

    it "should not set up for retrying the request" do
      flexmock(@instance).should_receive(:publish_with_timeout_retry).never
      @instance.send_persistent_request('/welcome/aboard', 'iZac', 'my-target') {|response|}
    end
  end

  describe "when handling a response" do
    before(:each) do
      flexmock(EM).should_receive(:next_tick).and_yield.by_default
      flexmock(EM).should_receive(:defer).and_yield.by_default
      @broker = flexmock("Broker", :subscribe => true, :publish => ["broker"], :connected? => true,
                         :identity_parts => ["host", 123, 0, 0, nil]).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker, :options => {:ping_interval => 0}).by_default
      RightScale::MapperProxy.new(@agent)
      @instance = RightScale::MapperProxy.instance
      flexmock(RightScale::AgentIdentity, :generate => 'token1')
    end

    it "should deliver the response" do
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      response = RightScale::Result.new('token1', 'to', RightScale::OperationResult.success, 'target1')
      flexmock(@instance).should_receive(:deliver).with(response, Hash).once
      @instance.handle_response(response)
    end

    it "should not deliver TARGET_NOT_CONNECTED and TTL_EXPIRATION responses for send_retryable_request" do
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      flexmock(@instance).should_receive(:deliver).never
      non_delivery = RightScale::OperationResult.non_delivery(RightScale::OperationResult::TARGET_NOT_CONNECTED)
      response = RightScale::Result.new('token1', 'to', non_delivery, 'target1')
      @instance.handle_response(response)
      non_delivery = RightScale::OperationResult.non_delivery(RightScale::OperationResult::TTL_EXPIRATION)
      response = RightScale::Result.new('token1', 'to', non_delivery, 'target1')
      @instance.handle_response(response)
    end

    it "should record non-delivery regardless of whether there is a response handler" do
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      non_delivery = RightScale::OperationResult.non_delivery(RightScale::OperationResult::NO_ROUTE_TO_TARGET)
      response = RightScale::Result.new('token1', 'to', non_delivery, 'target1')
      @instance.handle_response(response)
      @instance.instance_variable_get(:@non_deliveries).total.should == 1
    end

    it "should log non-delivery if there is no response handler" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Non-delivery of/).once
      @instance.send_push('/welcome/aboard', 'iZac') {|_|}
      non_delivery = RightScale::OperationResult.non_delivery(RightScale::OperationResult::NO_ROUTE_TO_TARGET)
      response = RightScale::Result.new('token1', 'to', non_delivery, 'target1')
      @instance.handle_response(response)
    end

    it "should log a debug message if request no longer pending" do
      flexmock(RightScale::RightLinkLog).should_receive(:debug).with(/No pending request for response/).once
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      @instance.pending_requests['token1'].should_not be_nil
      @instance.pending_requests['token2'].should be_nil
      response = RightScale::Result.new('token2', 'to', RightScale::OperationResult.success, 'target1')
      @instance.handle_response(response)
    end
  end

  describe "when delivering a response" do
    before(:each) do
      flexmock(EM).should_receive(:next_tick).and_yield.by_default
      flexmock(EM).should_receive(:defer).and_yield.by_default
      @broker = flexmock("Broker", :subscribe => true, :publish => ["broker"], :connected? => true,
                         :identity_parts => ["host", 123, 0, 0, nil]).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker, :options => {:ping_interval => 0}).by_default
      RightScale::MapperProxy.new(@agent)
      @instance = RightScale::MapperProxy.instance
      flexmock(RightScale::AgentIdentity, :generate => 'token1')
    end

    it "should delete all associated pending requests" do
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      @instance.pending_requests['token1'].should_not be_nil
      response = RightScale::Result.new('token1', 'to', RightScale::OperationResult.success, 'target1')
      @instance.handle_response(response)
      @instance.pending_requests['token1'].should be_nil
    end

    it "should delete any associated retry requests" do
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      @instance.pending_requests['token1'].should_not be_nil
      @instance.pending_requests['token2'] = @instance.pending_requests['token1'].dup
      @instance.pending_requests['token2'][:retry_parent] = 'token1'
      response = RightScale::Result.new('token2', 'to', RightScale::OperationResult.success, 'target1')
      @instance.handle_response(response)
      @instance.pending_requests['token1'].should be_nil
      @instance.pending_requests['token2'].should be_nil
    end

    it "should call the response handler" do
      called = 0
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|response| called += 1}
      response = RightScale::Result.new('token1', 'to', RightScale::OperationResult.success, 'target1')
      @instance.handle_response(response)
      called.should == 1
    end

    it "should defer the response handler call if not single threaded" do
      @agent.should_receive(:options).and_return({:single_threaded => false})
      RightScale::MapperProxy.new(@agent)
      @instance = RightScale::MapperProxy.instance
      called = 0
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|response| called += 1}
      response = RightScale::Result.new('token1', 'to', RightScale::OperationResult.success, 'target1')
      flexmock(EM).should_receive(:defer).and_yield.once
      flexmock(EM).should_receive(:next_tick).never
      @instance.handle_response(response)
      called.should == 1
    end

    it "should not defer the response handler call if single threaded" do
      @agent.should_receive(:options).and_return({:single_threaded => true})
      RightScale::MapperProxy.new(@agent)
      @instance = RightScale::MapperProxy.instance
      called = 0
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|response| called += 1}
      response = RightScale::Result.new('token1', 'to', RightScale::OperationResult.success, 'target1')
      flexmock(EM).should_receive(:next_tick).and_yield.once
      flexmock(EM).should_receive(:defer).never
      @instance.handle_response(response)
      called.should == 1
    end

    it "should log an error if the response handler raises an exception but still delete pending request" do
      @agent.should_receive(:options).and_return({:single_threaded => true})
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed processing response/, Exception, :trace).once
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_| raise Exception}
      @instance.pending_requests['token1'].should_not be_nil
      response = RightScale::Result.new('token1', 'to', RightScale::OperationResult.success, 'target1')
      @instance.handle_response(response)
      @instance.pending_requests['token1'].should be_nil
    end
  end

  describe "when use offline queueing" do
    before(:each) do
      @broker = flexmock("Broker", :subscribe => true, :publish => ["broker"], :connected? => true,
                         :identity_parts => ["host", 123, 0, 0, nil]).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker, :options => {}).by_default
      RightScale::MapperProxy.new(@agent)
      @instance = RightScale::MapperProxy.instance
      @instance.initialize_offline_queue
    end

    it 'should vote for reenroll after the maximum number of queued requests is reached' do
      @instance.instance_variable_get(:@reenroll_vote_count).should == 0
      EM.run do
        @instance.enable_offline_mode
        @instance.instance_variable_set(:@queue, ('*' * (RightScale::MapperProxy::MAX_QUEUED_REQUESTS - 1)).split(//))
        @instance.send_push('/dummy', 'payload', nil, :offline_queueing => true)
        EM.next_tick { EM.stop }
      end
      @instance.instance_variable_get(:@queue).size.should == RightScale::MapperProxy::MAX_QUEUED_REQUESTS
      @instance.instance_variable_get(:@reenroll_vote_count).should == 1
    end

    it 'should vote for reenroll after the threshold delay is reached' do
      old_vote_delay = RightScale::MapperProxy::REENROLL_VOTE_DELAY
      begin
        RightScale::MapperProxy.const_set(:REENROLL_VOTE_DELAY, 0.1)
        @instance.instance_variable_get(:@reenroll_vote_count).should == 0
        EM.run do
          @instance.enable_offline_mode
          @instance.send_push('/dummy', 'payload', nil, :offline_queueing => true)
          EM.add_timer(0.5) { EM.stop }
        end
        @instance.instance_variable_get(:@reenroll_vote_count).should == 1
      ensure
        RightScale::MapperProxy.const_set(:REENROLL_VOTE_DELAY, old_vote_delay)
      end
    end

    it 'should not flush queued requests until back online' do
      old_flush_delay = RightScale::MapperProxy::MAX_QUEUE_FLUSH_DELAY
      begin
        RightScale::MapperProxy.const_set(:MAX_QUEUE_FLUSH_DELAY, 0.1)
        EM.run do
          @instance.enable_offline_mode
          @instance.send_push('/dummy', 'payload', nil, :offline_queueing => true)
          EM.add_timer(0.5) { EM.stop }
        end
      ensure
        RightScale::MapperProxy.const_set(:MAX_QUEUE_FLUSH_DELAY, old_flush_delay)
      end
    end

    it 'should flush queued requests once back online' do
      old_flush_delay = RightScale::MapperProxy::MAX_QUEUE_FLUSH_DELAY
      @broker.should_receive(:publish).once.and_return { EM.stop }
      begin
        RightScale::MapperProxy.const_set(:MAX_QUEUE_FLUSH_DELAY, 0.1)
        EM.run do
          @instance.enable_offline_mode
          @instance.send_push('/dummy', 'payload', nil, :offline_queueing => true)
          @instance.disable_offline_mode
          EM.add_timer(1) { EM.stop }
        end
      ensure
        RightScale::MapperProxy.const_set(:MAX_QUEUE_FLUSH_DELAY, old_flush_delay)
      end
    end

    it 'should stop flushing when going back to offline mode' do
      old_flush_delay = RightScale::MapperProxy::MAX_QUEUE_FLUSH_DELAY
      begin
        RightScale::MapperProxy.const_set(:MAX_QUEUE_FLUSH_DELAY, 0.1)
        EM.run do
          @instance.enable_offline_mode
          @instance.send_push('/dummy', 'payload', nil, :offline_queueing => true)
          @instance.disable_offline_mode
          @instance.instance_variable_get(:@flushing_queue).should be_true
          @instance.instance_variable_get(:@stop_flushing_queue).should be_false
          @instance.instance_variable_get(:@queueing_mode).should == :offline
          @instance.enable_offline_mode
          @instance.instance_variable_get(:@flushing_queue).should be_true
          @instance.instance_variable_get(:@stop_flushing_queue).should be_true
          @instance.instance_variable_get(:@queueing_mode).should == :offline
          EM.add_timer(1) do
            @instance.instance_variable_get(:@flushing_queue).should be_false
            @instance.instance_variable_get(:@stop_flushing_queue).should be_false
            @instance.instance_variable_get(:@queueing_mode).should == :offline
            EM.stop
          end
        end
      ensure
        RightScale::MapperProxy.const_set(:MAX_QUEUE_FLUSH_DELAY, old_flush_delay)
      end
    end
  end

end
