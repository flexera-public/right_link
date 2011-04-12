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

describe RightScale::BrokerClient do

  include FlexMock::ArgumentTypes

  before(:each) do
#   flexmock(RightScale::RightLinkLog).should_receive(:error).with(on { |arg| puts caller.join("\n") } )
    flexmock(RightScale::RightLinkLog).should_receive(:error).never.by_default
    flexmock(RightScale::RightLinkLog).should_receive(:warning).never.by_default
    flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    @serializer = flexmock("serializer")
    @exceptions = flexmock("exception_stats")
    @exceptions.should_receive(:track).never.by_default
    @connection = flexmock("connection")
    @connection.should_receive(:connection_status).by_default
    flexmock(AMQP).should_receive(:connect).and_return(@connection).by_default
    @mq = flexmock("mq")
    @mq.should_receive(:connection).and_return(@connection).by_default
    @identity = "rs-broker-localhost-5672"
    @address = {:host => "localhost", :port => 5672, :index => 0}
    @options = {}
  end

  describe "Initializing connection" do

    before(:each) do
      @amqp = flexmock(AMQP)
      @amqp.should_receive(:connect).and_return(@connection).by_default
      @mq.should_receive(:prefetch).never.by_default
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
      @island = flexmock("island", :id => 2, :broker_hosts => "local_host").by_default
    end

    it "should create a broker with AMQP connection for specified address" do
      @amqp.should_receive(:connect).with(hsh(:user => "user", :pass => "pass", :vhost => "vhost", :host => "localhost",
                                              :port => 5672, :insist => true, :reconnect_interval => 10)).and_return(@connection).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, {:user => "user",
                                            :pass => "pass", :vhost => "vhost", :insist => true,
                                            :reconnect_interval => 10})
      broker.host.should == "localhost"
      broker.port.should == 5672
      broker.index.should == 0
      broker.queues.should == []
      broker.island_id.should be_nil
      broker.island_alias.should == ""
      broker.in_home_island.should be_true
      broker.summary.should == {:alias => "b0", :identity => @identity, :status => :connecting,
                                :disconnects => 0, :failures => 0, :retries => 0}
      broker.usable?.should be_true
      broker.connected?.should be_false
      broker.failed?.should be_false
    end

    it "should recognize the home island" do
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions,
                                            {:home_island => 2}, @island)
      broker.host.should == "localhost"
      broker.port.should == 5672
      broker.index.should == 0
      broker.queues.should == []
      broker.island_id.should == 2
      broker.island_alias.should == "i2"
      broker.in_home_island.should be_true
      broker.summary.should == {:alias => "b0", :identity => @identity, :status => :connecting,
                                :disconnects => 0, :failures => 0, :retries => 0}
    end

    it "should use island information when not home island" do
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions,
                                            {:home_island => 1}, @island)
      broker.host.should == "localhost"
      broker.port.should == 5672
      broker.index.should == 0
      broker.queues.should == []
      broker.island_id.should == 2
      broker.island_alias.should == "i2"
      broker.in_home_island.should be_false
      broker.summary.should == {:alias => "i2b0", :identity => @identity, :status => :connecting,
                                :disconnects => 0, :failures => 0, :retries => 0}
    end

    it "should update state from existing client for given broker" do
      existing = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      existing.__send__(:update_status, :disconnected)
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options, nil, existing)
      broker.summary.should == {:alias => "b0", :identity => @identity, :status => :connecting,
                                :disconnects => 1, :failures => 0, :retries => 0}
    end

    it "should log an info message when it creates an AMQP connection" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting to broker/).once
      RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
    end

    it "should log an error and set status to :failed if it fails to create an AMQP connection" do
      @exceptions.should_receive(:track).once
      @connection.should_receive(:close).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).once
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed connecting/, Exception, :trace).once
      flexmock(MQ).should_receive(:new).with(@connection).and_raise(Exception)
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.summary.should == {:alias => "b0", :identity => @identity, :status => :failed,
                                :disconnects => 0, :failures => 1, :retries => 0}
    end

    it "should set initialize connection status callback" do
      @connection.should_receive(:connection_status).once
      RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
    end

    it "should set broker prefetch value if specified" do
      @mq.should_receive(:prefetch).with(1).once
      RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, {:prefetch => 1})
    end

  end # Initializing

  describe "Subscribing" do

    before(:each) do
      @info = flexmock("info", :ack => true).by_default
      @message = flexmock("message")
      @packet = flexmock("packet", :class => RightScale::Request, :to_s => true, :version => [12, 12]).by_default
      @serializer.should_receive(:load).with(@message).and_return(@packet).by_default
      @direct = flexmock("direct")
      @fanout = flexmock("fanout")
      @bind = flexmock("bind")
      @queue = flexmock("queue")
      @queue.should_receive(:bind).and_return(@bind).by_default
      @mq.should_receive(:queue).and_return(@queue).by_default
      @mq.should_receive(:direct).and_return(@direct).by_default
      @mq.should_receive(:fanout).and_return(@fanout).by_default
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
    end

    it "should subscribe queue to exchange" do
      @queue.should_receive(:bind).and_return(@bind).once
      @bind.should_receive(:subscribe).and_yield(@message).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      broker.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}) {|b, p| p.should == nil}
    end

    it "should subscribe queue to second exchange if specified" do
      @queue.should_receive(:bind).and_return(@bind).twice
      @bind.should_receive(:subscribe).and_yield(@message).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      options = {:exchange2 => {:type => :fanout, :name => "exchange2", :options => {:durable => true}}}
      broker.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}, options) {|b, p| p.should == nil}
    end

    it "should subscribe queue to exchange when still connecting" do
      @bind.should_receive(:subscribe).and_yield(@message).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}) {|b, p| p.should == nil}
    end

    it "should subscribe queue to empty exchange if no exchange specified" do
      @queue.should_receive(:subscribe).and_yield(@message).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      broker.subscribe({:name => "queue"}) {|b, p| p.should == nil}
    end

    it "should store queues for future reference" do
      @bind.should_receive(:subscribe).and_yield(@message).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"})
      broker.queues.should == [@queue]
    end

    it "should return true if subscribed successfully" do
      @bind.should_receive(:subscribe).and_yield(@message)
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      result = broker.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}) {|b, p| p.should == nil}
      result.should be_true
    end

    it "should ack received message if requested" do
      @info.should_receive(:ack).once
      @bind.should_receive(:subscribe).and_yield(@info, @message).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      result = broker.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"},
                                :ack => true) {|b, p| p.should == nil}
      result.should be_true
    end

    it "should return false if client not usable" do
      @queue.should_receive(:bind).and_return(@bind).never
      @bind.should_receive(:subscribe).and_yield(@message).never
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :disconnected)
      broker.subscribe({:name => "queue"}).should be_false
    end
 
    it "should receive message causing it to be unserialized and logged" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Subscribing/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/RECV/).once
      @serializer.should_receive(:load).with(@message).and_return(@packet).once
      @bind.should_receive(:subscribe).and_yield(@message).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      broker.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"},
                       RightScale::Request => nil) {|b, p| p.class.should == RightScale::Request}
    end

    it "should receive message and log exception if subscribe block fails" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Subscribing/).once
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed executing block/, Exception, :trace).once
      @exceptions.should_receive(:track).once
      @serializer.should_receive(:load).with(@message).and_return(@packet).once
      @bind.should_receive(:subscribe).and_yield(@message).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      result = broker.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"},
                                RightScale::Request => nil) {|b, p| raise Exception}
      result.should be_false
    end

    it "should ignore 'nil' message when using ack" do
      flexmock(RightScale::RightLinkLog).should_receive(:level).and_return(:debug)
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Subscribing/).once
      flexmock(RightScale::RightLinkLog).should_receive(:debug).with(/nil message ignored/).once
      @bind.should_receive(:subscribe).and_yield(@info, "nil").once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      called = 0
      broker.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}, :ack => true) { |b, m| called += 1 }
      called.should == 0
    end

    it "should ignore 'nil' message when not using ack" do
      flexmock(RightScale::RightLinkLog).should_receive(:level).and_return(:debug)
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Subscribing/).once
      flexmock(RightScale::RightLinkLog).should_receive(:debug).with(/nil message ignored/).once
      @bind.should_receive(:subscribe).and_yield("nil").once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      called = 0
      broker.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}) { |b, m| called += 1 }
      called.should == 0
    end

    it "should not unserialize the message if requested" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Subscribing/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV/).never
      @bind.should_receive(:subscribe).and_yield(@message).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      broker.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}, :no_unserialize => true) do |b, m|
        b.should == "rs-broker-localhost-5672"
        m.should == @message
      end
    end

    it "should log an error if a subscribe fails" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/RECV/).never
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed subscribing/, Exception, :trace).once
      @exceptions.should_receive(:track).once
      @bind.should_receive(:subscribe).and_raise(Exception)
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      result = broker.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}) {|b, p|}
      result.should be_false
    end

  end # Subscribing

  describe "Receiving" do

    before(:each) do
      @message = flexmock("message")
      @packet = flexmock("packet", :class => RightScale::Request, :to_s => true, :version => [12, 12]).by_default
      @serializer.should_receive(:load).with(@message).and_return(@packet).once.by_default
    end

    it "should unserialize the message, log it, and return it" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV/).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:receive, "queue", @message, RightScale::Request => nil).should == @packet
    end

    it "should log a warning if the message is not of the right type and return nil" do
      flexmock(RightScale::RightLinkLog).should_receive(:warn).with(/Received invalid.*packet type/).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:receive, "queue", @message).should be_nil
    end

    it "should show the category in the warning message if specified" do
      flexmock(RightScale::RightLinkLog).should_receive(:warn).with(/Received invalid xxxx packet type/).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:receive, "queue", @message, RightScale::Result => nil, :category => "xxxx")
    end

    it "should display broker alias in the log" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV b0 /).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:receive, "queue", @message, RightScale::Request => nil)
    end

    it "should filter the packet display for :info level" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV.*TO YOU/).once
      flexmock(RightScale::RightLinkLog).should_receive(:debug).with(/^RECV.*TO YOU/).never
      @packet.should_receive(:to_s).with([:to], :recv_version).and_return("TO YOU").once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:receive, "queue", @message, RightScale::Request => [:to])
    end

    it "should not filter the packet display for :debug level" do
      flexmock(RightScale::RightLinkLog).should_receive(:level).and_return(:debug)
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV.*ALL/).never
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV.*ALL/).once
      @packet.should_receive(:to_s).with(nil, :recv_version).and_return("ALL").once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:receive, "queue", @message, RightScale::Request => [:to])
    end

    it "should display additional data in log" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV.*More data/).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:receive, "queue", @message, RightScale::Request => nil, :log_data => "More data")
    end

    it "should not log a message if requested not to" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV/).never
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:receive, "queue", @message, RightScale::Request => nil, :no_log => true)
    end

    it "should not log a message if requested not to unless debug level" do
      flexmock(RightScale::RightLinkLog).should_receive(:level).and_return(:debug)
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV/).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:receive, "queue", @message, RightScale::Request => nil, :no_log => true)
    end

    it "should log an error if exception prevents normal logging and should then return nil" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed receiving from queue/, Exception, :trace).once
      @serializer.should_receive(:load).with(@message).and_raise(Exception).once
      @exceptions.should_receive(:track).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:receive, "queue", @message).should be_nil
    end

    it "should make callback when there is a receive failure" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed receiving from queue/, Exception, :trace).once
      @serializer.should_receive(:load).with(@message).and_raise(Exception).once
      @exceptions.should_receive(:track).once
      called = 0
      callback = lambda { |msg, e| called += 1 }
      options = {:exception_on_receive_callback => callback}
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, options)
      broker.__send__(:receive, "queue", @message).should be_nil
      called.should == 1
    end

    it "should display RE-RECV if the message being received is a retry" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RE-RECV/).once
      @packet.should_receive(:tries).and_return(["try1"]).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:receive, "queue", @message, RightScale::Request => nil).should == @packet
    end

  end # Receiving

  describe "Unsubscribing" do

    before(:each) do
      @direct = flexmock("direct")
      @bind = flexmock("bind", :subscribe => true)
      @queue = flexmock("queue", :bind => @bind, :name => "queue1")
      @mq.should_receive(:queue).and_return(@queue).by_default
      @mq.should_receive(:direct).and_return(@direct).by_default
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
    end

    it "should unsubscribe a queue by name" do
      @queue.should_receive(:unsubscribe).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      broker.unsubscribe(["queue1"])
    end

    it "should ignore unsubscribe if queue unknown" do
      @queue.should_receive(:unsubscribe).never
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      broker.unsubscribe(["queue2"])
    end

    it "should activate block after unsubscribing if provided" do
      @queue.should_receive(:unsubscribe).and_yield.once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      called = 0
      broker.unsubscribe(["queue1"]) { called += 1 }
      called.should == 1
    end

    it "should ignore the request if client not usable" do
      @queue.should_receive(:unsubscribe).and_yield.never
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      broker.__send__(:update_status, :disconnected)
      broker.unsubscribe(["queue1"])
    end

    it "should log an error if unsubscribe raises an exception and activate block if provided" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed unsubscribing/, Exception, :trace).once
      @queue.should_receive(:unsubscribe).and_raise(Exception).once
      @exceptions.should_receive(:track).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      called = 0
      broker.unsubscribe(["queue1"]) { called += 1 }
      called.should == 1
    end

  end # Unsubscribing

  describe "Declaring" do

    before(:each) do
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
      @mq.should_receive(:queues).and_return({}).by_default
      @mq.should_receive(:exchanges).and_return({}).by_default
    end

    it "should declare exchange and return true" do
      @mq.should_receive(:exchange).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.declare(:exchange, "x", :durable => true).should be_true
    end

    it "should delete the exchange or queue from the AMQP cache before declaring" do
      @mq.should_receive(:queue).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      flexmock(broker).should_receive(:delete_from_cache).with(:queue, "queue").once
      broker.declare(:queue, "queue", :durable => true).should be_true
    end

    it "should log declaration" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Declaring/).once
      @mq.should_receive(:queue).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.declare(:queue, "q").should be_true
    end

    it "should return false if client not usable" do
      @mq.should_receive(:exchange).never
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :disconnected)
      broker.declare(:exchange, "x", :durable => true).should be_false

    end

    it "should log an error if the declare fails and return false" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Declaring/).once
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed declaring/, Exception, :trace).once
      @exceptions.should_receive(:track).once
      @mq.should_receive(:queue).and_raise(Exception).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.declare(:queue, "q").should be_false
    end

  end # Declaring

  describe "Publishing" do

    before(:each) do
      @message = flexmock("message")
      @packet = flexmock("packet", :class => RightScale::Request, :to_s => true, :version => [12, 12]).by_default
      @direct = flexmock("direct")
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
    end

    it "should serialize message, publish it, and return true" do
      @mq.should_receive(:direct).with("exchange", :durable => true).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, :persistent => true).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      broker.publish({:type => :direct, :name => "exchange", :options => {:durable => true}},
                     @packet, @message, :persistent => true).should be_true
    end

    it "should delete the exchange or queue from the AMQP cache if :declare specified" do
      @mq.should_receive(:direct).with("exchange", {:declare => true}).and_return(@direct)
      @direct.should_receive(:publish).with(@message, {})
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      exchange = {:type => :direct, :name => "exchange", :options => {:declare => true}}
      flexmock(broker).should_receive(:delete_from_cache).with(:direct, "exchange").once
      broker.publish(exchange, @packet, @message).should be_true
    end

    it "should return false if client not connected" do
      @mq.should_receive(:direct).never
      @direct.should_receive(:publish).with(@message, :persistent => true).never
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.publish({:type => :direct, :name => "exchange", :options => {:durable => true}},
                     @packet, @message, :persistent => true).should be_false
    end

    it "should log an error if the publish fails" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed publishing/, Exception, :trace).once
      @exceptions.should_receive(:track).once
      @mq.should_receive(:direct).and_raise(Exception)
      @direct.should_receive(:publish).with(@message, {}).never
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      broker.publish({:type => :direct, :name => "exchange"}, @packet, @message).should be_false
    end

    it "should log that message is being sent with info about which broker used" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND b0/).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, {}).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      broker.publish({:type => :direct, :name => "exchange"}, @packet, @message).should be_true
    end

    it "should log broker choices for :debug level" do
      flexmock(RightScale::RightLinkLog).should_receive(:level).and_return(:debug)
      flexmock(RightScale::RightLinkLog).should_receive(:debug).with(/... publish options/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND b0/).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, {}).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      broker.publish({:type => :direct, :name => "exchange"}, @packet, @message).should be_true
    end

    it "should not log a message if requested not to" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND/).never
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, :no_log => true).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      broker.publish({:type => :direct, :name => "exchange"}, @packet, @message, :no_log => true).should be_true
    end

    it "should not log a message if requested not to unless debug level" do
      flexmock(RightScale::RightLinkLog).should_receive(:level).and_return(:debug)
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND/).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, :no_log => true).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      broker.publish({:type => :direct, :name => "exchange"}, @packet, @message, :no_log => true).should be_true
    end

    it "should display broker alias in the log" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND b0 /).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, {}).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      broker.publish({:type => :direct, :name => "exchange"}, @packet, @message).should be_true
    end

    it "should filter the packet display for :info level" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND.*TO YOU/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND.*TO YOU/).never
      @packet.should_receive(:to_s).with([:to], :send_version).and_return("TO YOU").once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, :log_filter => [:to]).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      broker.publish({:type => :direct, :name => "exchange"}, @packet, @message, :log_filter => [:to]).should be_true
    end

    it "should not filter the packet display for :debug level" do
      flexmock(RightScale::RightLinkLog).should_receive(:level).and_return(:debug)
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND.*ALL/).never
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND.*ALL/).once
      @packet.should_receive(:to_s).with(nil, :send_version).and_return("ALL").once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, :log_filter => [:to]).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      broker.publish({:type => :direct, :name => "exchange"}, @packet, @message, :log_filter => [:to]).should be_true
    end
    
    it "should display additional data in log" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND.*More data/).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, :log_data => "More data").once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      broker.publish({:type => :direct, :name => "exchange"}, @packet, @message, :log_data => "More data").should be_true
    end

    it "should display RE-SEND if the message being sent is a retry" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RE-SEND/).once
      @packet = flexmock("packet", :class => RightScale::Request, :to_s => true, :tries => ["try1"], :version => [12, 12])
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, {}).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :ready)
      broker.publish({:type => :direct, :name => "exchange"}, @packet, @message).should be_true
    end

  end # Publishing

  describe "Returning" do

    class MQ
      attr_accessor :connection, :on_return_message

      def initialize(connection)
        @connection = connection
      end

      def return_message(&blk)
        @on_return_message = blk
      end
    end

    before(:each) do
      @message = flexmock("message")
      @packet = flexmock("packet", :class => RightScale::Request, :to_s => true, :version => [12, 12]).by_default
      @info = flexmock("info", :reply_text => "NO_CONSUMERS", :exchange => "exchange", :routing_key => "routing_key").by_default
      @serializer.should_receive(:load).with(@message).and_return(@packet).by_default
    end

    it "should invoke block and log the return" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting to broker/).once
      flexmock(RightScale::RightLinkLog).should_receive(:debug).with(/RETURN b0/).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      called = 0
      broker.return_message do |to, reason, message|
        called += 1
        to.should == "exchange"
        reason.should == "NO_CONSUMERS"
        message.should == @message
      end
      broker.instance_variable_get(:@mq).on_return_message.call(@info, @message)
      called.should == 1
    end

    it "should invoke block with routing key if exchange is empty" do
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      called = 0
      broker.return_message do |to, reason, message|
        called += 1
        to.should == "routing_key"
        reason.should == "NO_CONSUMERS"
        message.should == @message
      end
      @info.should_receive(:exchange).and_return("")
      broker.instance_variable_get(:@mq).on_return_message.call(@info, @message)
      called.should == 1
    end

    it "should log an error if there is a failure while processing the return" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed return/, Exception, :trace).once
      @exceptions.should_receive(:track).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      called = 0
      broker.return_message do |to, reason, message|
        called += 1
        raise Exception
      end
      broker.instance_variable_get(:@mq).on_return_message.call(@info, @message)
      called.should == 1
    end

  end # Returning

  describe "Deleting" do

    before(:each) do
      @direct = flexmock("direct")
      @bind = flexmock("bind", :subscribe => true)
      @queue = flexmock("queue", :bind => @bind, :name => "queue1")
      @mq.should_receive(:queue).and_return(@queue).by_default
      @mq.should_receive(:direct).and_return(@direct).by_default
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
    end

    it "should delete the named queue and return true" do
      @queue.should_receive(:delete).once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      broker.queues.should == [@queue]
      broker.delete("queue1").should be_true
      broker.queues.should == []
    end

    it "should return false if the client is not usable" do
      @queue.should_receive(:delete).never
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      broker.queues.should == [@queue]
      broker.__send__(:update_status, :disconnected)
      broker.delete("queue1").should be_false
      broker.queues.should == [@queue]
    end

    it "should log an error and return false if the delete fails" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed deleting queue/, Exception, :trace).once
      @exceptions.should_receive(:track).once
      @queue.should_receive(:delete).and_raise(Exception)
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      broker.queues.should == [@queue]
      broker.delete("queue1").should be_false
    end

  end # Deleteing

  describe "Monitoring" do

    include RightScale::StatsHelper

    before(:each) do
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
    end

    it "should distinguish whether the client is usable based on whether connecting or connected" do
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.usable?.should be_true
      broker.__send__(:update_status, :ready)
      broker.usable?.should be_true
      broker.__send__(:update_status, :disconnected)
      broker.usable?.should be_false
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed to connect to broker b0/).once
      broker.__send__(:update_status, :failed)
      broker.usable?.should be_false
    end

    it "should distinguish whether the client is connected" do
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.connected?.should be_false
      broker.__send__(:update_status, :ready)
      broker.connected?.should be_true
      broker.__send__(:update_status, :disconnected)
      broker.connected?.should be_false
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed to connect to broker b0/).once
      broker.__send__(:update_status, :failed)
      broker.connected?.should be_false
    end

    it "should distinguish whether the client has failed" do
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.failed?.should be_false
      broker.__send__(:update_status, :ready)
      broker.failed?.should be_false
      broker.__send__(:update_status, :disconnected)
      broker.failed?.should be_false
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed to connect to broker b0/).once
      broker.__send__(:update_status, :failed)
      broker.failed?.should be_true
    end
 
    it "should give broker summary" do
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.summary.should == {:alias => "b0", :identity => @identity, :status => :connecting,
                                :disconnects => 0, :failures => 0, :retries => 0}
      broker.__send__(:update_status, :ready)
      broker.summary.should == {:alias => "b0", :identity => @identity, :status => :connected,
                                :disconnects => 0, :failures => 0, :retries => 0}
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed to connect to broker/).once
      broker.__send__(:update_status, :failed)
      broker.summary.should == {:alias => "b0", :identity => @identity, :status => :failed,
                                :disconnects => 0, :failures => 1, :retries => 0}
    end

    it "should give broker statistics" do
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.stats.should == {"alias" => "b0", "identity" => "rs-broker-localhost-5672",
                              "status" => "connecting", "disconnects" => nil, "disconnect last" => nil,
                              "failures" => nil, "failure last" => nil, "retries" => nil}
      broker.__send__(:update_status, :ready)
      broker.stats.should == {"alias" => "b0", "identity" => "rs-broker-localhost-5672",
                              "status" => "connected", "disconnects" => nil, "disconnect last" => nil,
                              "failures" => nil, "failure last" => nil, "retries" => nil}
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed to connect to broker/).once
      broker.__send__(:update_status, :failed)
      broker.stats.should == {"alias" => "b0", "identity" => "rs-broker-localhost-5672",
                              "status" => "failed", "disconnects" => nil, "disconnect last" => nil,
                              "failures" => 1, "failure last" => {"elapsed" => 0}, "retries" => nil}
    end

    it "should make update status callback when status changes" do
      broker = nil
      called = 0
      connected_before = false
      callback = lambda { |b, c| called += 1; b.should == broker; c.should == connected_before }
      options = {:update_status_callback => callback}
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, options)
      broker.__send__(:update_status, :ready)
      broker.last_failed.should be_false
      called.should == 1
      connected_before = true
      broker.__send__(:update_status, :disconnected)
      broker.last_failed.should be_false
      broker.disconnects.total.should == 1
      called.should == 2
      broker.__send__(:update_status, :disconnected)
      broker.disconnects.total.should == 1
      called.should == 2
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed to connect to broker b0/).once
      connected_before = false
      broker.__send__(:update_status, :failed)
      broker.last_failed.should be_true
      called.should == 3
    end

  end # Monitoring

  describe "Closing" do

    before(:each) do
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
    end

    it "should close broker connection and send status update" do
      @connection.should_receive(:close).and_yield.once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      flexmock(broker).should_receive(:update_status).once
      broker.close
      broker.status.should == :closed
    end

    it "should not propagate status update if requested not to" do
      @connection.should_receive(:close).and_yield.once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      flexmock(broker).should_receive(:update_status).never
      broker.close(propagate = false)
    end

    it "should set status to :failed if not a normal close" do
      @connection.should_receive(:close).and_yield.once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.close(propagate = false, normal = false)
      broker.status.should == :failed
    end

    it "should log that closing connection" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Closed connection to broker b0/).once
      @connection.should_receive(:close).and_yield.once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.close
    end

    it "should not log if requested not to" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Closed connection to broker b0/).never
      @connection.should_receive(:close).and_yield.once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.close(propagate = true, normal = true, log = false)
    end

    it "should close broker connection and execute block if supplied" do
      @connection.should_receive(:close).and_yield.once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      called = 0
      broker.close { called += 1; broker.status.should == :closed }
      called.should == 1
    end

    it "should close broker connection when no block supplied" do
      @connection.should_receive(:close).and_yield.once
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.close
    end

    it "should not propagate status update if already closed" do
      @connection.should_receive(:close).never
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :closed)
      flexmock(broker).should_receive(:update_status).never
      broker.close
    end

    it "should change failed status to closed" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed to connect to broker/).once
      @connection.should_receive(:close).never
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.__send__(:update_status, :failed)
      flexmock(broker).should_receive(:update_status).never
      broker.close
      broker.status.should == :closed
    end

    it "should log an error if closing connection fails but still set status to :closed" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed to close broker b0/, Exception, :trace).once
      @exceptions.should_receive(:track).once
      @connection.should_receive(:close).and_raise(Exception)
      broker = RightScale::BrokerClient.new(@identity, @address, @serializer, @exceptions, @options)
      broker.close
      broker.status.should == :closed
    end

  end # Closing

end # RightScale::HABrokerClient
