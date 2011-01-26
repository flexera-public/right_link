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
require 'tmpdir'

describe RightScale::HA_MQ do

  include FlexMock::ArgumentTypes

  describe "Caching" do

    before(:each) do
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
      @published = RightScale::HA_MQ::Published.new
      @message1 = MessagePack.dump(:signature => "signature1")
      @key1 = @message1[@message1 =~ /signature/, 1000]
      @message2 = JSON.dump(:signature => "signature2")
      @key2 = @message2[@message2 =~ /signature/, 1000]
      @message3 = MessagePack.dump(:data => "just data")
      @key3 = @message3
      @packet1 = flexmock("packet1", :class => RightScale::Request, :name => "request", :type => "type1",
                          :from => "from1", :token => "token1", :one_way => false)
      @packet2 = flexmock("packet2", :class => RightScale::Request, :name => "request", :type => "type2",
                          :from => "from2", :token => "token2", :one_way => false)
      @packet3 = flexmock("packet3", :class => RightScale::Push, :name => "push", :type => "type3",
                          :from => "from3", :token => "token3", :one_way => true)
      @brokers = ["broker"]
      @options = {:option => "option"}
      @details1 = {:name => "request", :type => "type1", :from => "from1", :token => "token1", :one_way => false,
                   :options => @options, :brokers => @brokers, :failed => []}
      @details2 = {:name => "request", :type => "type2", :from => "from2", :token => "token2", :one_way => false,
                   :options => @options, :brokers => @brokers, :failed => []}
      @details3 = {:name => "push", :type => "type3", :from => "from3", :token => "token3", :one_way => true,
                   :options => @options, :brokers => @brokers, :failed => []}
    end

    it "should use message signature as cache hash key if it has one" do
      @published.identify(@message1).should == @key1
      @published.identify(@message2).should == @key2
      @published.identify(@message3).should == @key3
    end

    it "should store message info" do
      @published.store(@message1, @packet1, @brokers, @options)
      @published.instance_variable_get(:@cache)[@key1].should == [1000000, @details1]
      @published.instance_variable_get(:@lru).should == [@key1]
    end

    it "should treat type, from, token, and one_way as optional members of packet but default one_way to true" do
      @published.store(@message1, nil, nil, nil)
      @published.instance_variable_get(:@cache)[@key1].should ==
              [1000000, {:name => "nil_class", :type => nil, :from => nil, :token => nil, :one_way => true,
                         :options => nil, :brokers => nil, :failed => []}]
      @published.instance_variable_get(:@lru).should == [@key1]
    end

    it "should update timestamp and lru list when store to existing entry" do
      @published.store(@message1, @packet1, @brokers, @options)
      @published.instance_variable_get(:@cache)[@key1].should == [1000000, @details1]
      @published.instance_variable_get(:@lru).should == [@key1]
      @published.store(@message2, @packet2, @brokers, @options)
      @published.instance_variable_get(:@lru).should == [@key1, @key2]
      flexmock(Time).should_receive(:now).and_return(Time.at(1000010))
      @published.store(@message1, @packet1, @brokers, @options)
      @published.instance_variable_get(:@cache)[@key1].should == [1000010, @details1]
      @published.instance_variable_get(:@lru).should == [@key2, @key1]
    end

    it "should remove old cache entries when store new one" do
      @published.store(@message1, @packet1, @brokers, @options)
      @published.store(@message2, @packet2, @brokers, @options)
      @published.instance_variable_get(:@cache).keys.should == [@key1, @key2]
      @published.instance_variable_get(:@lru).should == [@key1, @key2]
      flexmock(Time).should_receive(:now).and_return(Time.at(1000031))
      @published.store(@message3, @packet3, @brokers, @options)
      @published.instance_variable_get(:@cache).keys.should == [@key3]
      @published.instance_variable_get(:@lru).should == [@key3]
    end

    it "should fetch message info and make it the most recently used" do
      @published.store(@message1, @packet1, @brokers, @options)
      @published.store(@message2, @packet2, @brokers, @options)
      @published.instance_variable_get(:@lru).should == [@key1, @key2]
      @published.fetch(@message1).should == @details1
      @published.instance_variable_get(:@lru).should == [@key2, @key1]
    end

    it "should fetch empty hash if entry not found" do
      @published.fetch(@message1).should == {}
      @published.store(@message1, @packet, @brokers, @options)
      @published.fetch(@message1).should_not == {}
      @published.fetch(@message2).should == {}
    end

  end # Published

  describe "Addressing" do

    it "should form list of broker addresses from specified hosts and ports" do
      RightScale::HA_MQ.addresses("first,second", "5672, 5674").should ==
        [{:host => "first", :port => 5672, :id => 0}, {:host => "second", :port => 5674, :id => 1}]
    end

    it "should form list of broker addresses from specified hosts and ports and use ids associated with hosts" do
      RightScale::HA_MQ.addresses("first:1,second:2", "5672, 5674").should ==
        [{:host => "first", :port => 5672, :id => 1}, {:host => "second", :port => 5674, :id => 2}]
    end

    it "should form list of broker addresses from specified hosts and ports and use ids associated with ports" do
      RightScale::HA_MQ.addresses("host", "5672:0, 5674:2").should ==
        [{:host => "host", :port => 5672, :id => 0}, {:host => "host", :port => 5674, :id => 2}]
    end

    it "should use default host and port for broker identity if none provided" do
      RightScale::HA_MQ.addresses(nil, nil).should == [{:host => "localhost", :port => 5672, :id => 0}]
    end

    it "should reuse host if there is only one but multiple ports" do
      RightScale::HA_MQ.addresses("first", "5672, 5674").should ==
        [{:host => "first", :port => 5672, :id => 0}, {:host => "first", :port => 5674, :id => 1}]
    end

    it "should reuse port if there is only one but multiple hosts" do
      RightScale::HA_MQ.addresses("first, second", 5672).should ==
        [{:host => "first", :port => 5672, :id => 0}, {:host => "second", :port => 5672, :id => 1}]
    end

    it "should apply ids associated with host" do
      RightScale::HA_MQ.addresses("first:0, third:2", 5672).should ==
        [{:host => "first", :port => 5672, :id => 0}, {:host => "third", :port => 5672, :id => 2}]
    end

    it "should not allow mismatched number of hosts and ports" do
      runner = lambda { RightScale::HA_MQ.addresses("first, second", "5672, 5673, 5674") }
      runner.should raise_exception(ArgumentError)
    end

  end # Addressing

  describe "Initializing" do

    before(:each) do
      @serializer = flexmock("Serializer")
      @connection = flexmock("connection", :connection_status => true).by_default
      flexmock(AMQP).should_receive(:connect).and_return(@connection).by_default
      @mq = flexmock("mq", :connection => @connection, :return_message => true).by_default
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
      flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    end

    it "should create a broker with AMQP connection for default host and port" do
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.status.should == [{:alias => "b0", :identity => "rs-broker-localhost-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0}]
    end

    it "should create AMQP connections for specified hosts and ports and assign alias id in order of creation" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second", :port => 5672)
      ha_mq.status.should == [{:alias => "b0", :identity => "rs-broker-first-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0},
                              {:alias => "b1", :identity => "rs-broker-second-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0}]
    end

    it "should create AMQP connections for specified hosts and ports and assign alias id as assigned per host" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha_mq.status.should == [{:alias => "b0", :identity => "rs-broker-first-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0},
                              {:alias => "b2", :identity => "rs-broker-third-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0}]
    end

    it "should create AMQP connections for specified hosts and ports and assign alias id as assigned per port" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "host", :port => "5672:0,5673:2")
      ha_mq.status.should == [{:alias => "b0", :identity => "rs-broker-host-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0},
                              {:alias => "b2", :identity => "rs-broker-host-5673", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0}]
    end

    it "should log an info message when it creates an AMQP connection" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting to broker/).twice
      RightScale::HA_MQ.new(@serializer, :host => "first, second", :port => 5672)
    end

    it "should log an error if it fails to create an AMQP connection" do
      @connection.should_receive(:close).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).once
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed connecting/, Exception, :trace).once
      flexmock(MQ).should_receive(:new).with(@connection).and_raise(Exception)
      RightScale::HA_MQ.new(@serializer)
    end

    it "should allow prefetch value to be set for all usable brokers" do
      @mq.should_receive(:prefetch).times(3)
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second", :port => 5672)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.brokers[1][:status] = :connected
      ha_mq.prefetch(1)
      ha_mq.brokers[0][:status] = :disconnected
      ha_mq.brokers[1][:status] = :connected
      ha_mq.prefetch(1)
    end

    it "should setup to receive returned messages from each broker" do
      @mq.should_receive(:return_message).twice
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
    end

  end # Initializing

  describe "Identifying" do

    before(:each) do
      @serializer = flexmock("Serializer")
      @connection = flexmock("connection", :connection_status => true).by_default
      flexmock(AMQP).should_receive(:connect).and_return(@connection).by_default
      @mq = flexmock("mq", :connection => @connection, :return_message => true)
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
      flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    end

    it "should use host and port to uniquely identity broker in AgentIdentity format" do
      RightScale::HA_MQ.identity("localhost", 5672).should == "rs-broker-localhost-5672"
      RightScale::HA_MQ.identity("10.21.102.23", 1234).should == "rs-broker-10.21.102.23-1234"
    end

    it "should replace '-' with '~' in host names when forming broker identity" do
      RightScale::HA_MQ.identity("9-1-1", 5672).should == "rs-broker-9~1~1-5672"
    end

    it "should obtain host and port from a broker's identity" do
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.__send__(:host, "rs-broker-localhost-5672").should == "localhost"
      ha_mq.__send__(:port, "rs-broker-localhost-5672").should == 5672
      ha_mq.__send__(:host, "rs-broker-10.21.102.23-1234").should == "10.21.102.23"
      ha_mq.__send__(:port, "rs-broker-10.21.102.23-1234").should == 1234
      ha_mq.__send__(:host, "rs-broker-9~1~1-5672").should == "9-1-1"
      ha_mq.__send__(:port, "rs-broker-9~1~1-5672").should == 5672
    end

    it "should list broker identities" do
      RightScale::HA_MQ.identities("first,second", "5672, 5674").should ==
        ["rs-broker-first-5672", "rs-broker-second-5674"]
    end

    it "should convert identities into aliases" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha_mq.aliases(["rs-broker-third-5672"]).should == ["b2"]
      ha_mq.aliases(["rs-broker-third-5672", "rs-broker-first-5672"]).should == ["b2", "b0"]
    end

    it "should convert identities into nil alias when unknown" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha_mq.aliases(["rs-broker-second-5672", nil]).should == [nil, nil]
    end

    it "should convert identity into alias" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha_mq.alias_("rs-broker-third-5672").should == "b2"
    end

    it "should convert identity into nil alias when unknown" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha_mq.alias_("rs-broker-second-5672").should == nil
    end

    it "should convert identity into parts" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha_mq.identity_parts("rs-broker-third-5672").should == ["third", 5672, 2, 1]
    end

    it "should convert an alias into parts" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha_mq.identity_parts("b2").should == ["third", 5672, 2, 1]
    end

    it "should convert an alias id into parts" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha_mq.identity_parts(2).should == ["third", 5672, 2, 1]
    end

    it "should convert unknown identity into nil parts" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha_mq.identity_parts("rs-broker-second-5672").should == [nil, nil, nil, nil]
    end

    it "should get identity from identity" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha_mq.get("rs-broker-first-5672").should == "rs-broker-first-5672"
      ha_mq.get("rs-broker-second-5672").should == nil
      ha_mq.get("rs-broker-third-5672").should == "rs-broker-third-5672"
    end

    it "should get identity from an alias" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha_mq.get("b0").should == "rs-broker-first-5672"
      ha_mq.get("b1").should == nil
      ha_mq.get("b2").should == "rs-broker-third-5672"
    end

    it "should get identity from an alias id" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha_mq.get(0).should == "rs-broker-first-5672"
      ha_mq.get(1).should == nil
      ha_mq.get(2).should == "rs-broker-third-5672"
    end

    it "should generate host:id list" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first:11, second:0", :port => 5672)
      ha_mq.hosts.should == "first:11,second:0"
    end

    it "should generate port:id list" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first:1, second:22", :port => 5672)
      ha_mq.ports.should == "5672:1,5672:22"
    end

    it "should return default host" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first:0, second:1")
      ha_mq.default_host.should == "first"
    end

    it "should retun nil default host if no broker has id 0" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first:1, second:2")
      ha_mq.default_host.should be_nil
    end

  end # Identifying

  describe "Subscribing" do

    before(:each) do
      @info = flexmock("info", :ack => true).by_default
      @message = flexmock("message")
      @packet = flexmock("packet", :class => RightScale::Request, :to_s => true, :version => [12, 12]).by_default
      @serializer = flexmock("Serializer", :load => @packet).by_default
      @direct = flexmock("direct")
      @fanout = flexmock("fanout")
      @bind = flexmock("bind")
      @queue = flexmock("queue", :bind => @bind).by_default
      @connection = flexmock("connection", :connection_status => true).by_default
      flexmock(AMQP).should_receive(:connect).and_return(@connection).by_default
      @mq = flexmock("mq", :queue => @queue, :direct => @direct, :fanout => @fanout,
                     :connection => @connection, :return_message => true)
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
      flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    end

    it "should subscribe queue to exchange" do
      @queue.should_receive(:bind).and_return(@bind).once
      @bind.should_receive(:subscribe).and_yield(@message).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}) {|b, p| p.should == nil}
    end

    it "should subscribe queue to exchange for each selected, usable brokers" do
      @queue.should_receive(:bind).and_return(@bind).once
      @bind.should_receive(:subscribe).and_yield(@message).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second, third")
      ha_mq.brokers[0][:status] = :connected
      ha_mq.brokers[1][:status] = :connected
      ha_mq.brokers[2][:status] = :disconnected
      options = {:brokers => ["rs-broker-third-5672", "rs-broker-second-5672"]}
      ha_mq.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}, options) {|b, p| p.should == nil}
    end

    it "should subscribe queue to second exchange if specified" do
      @queue.should_receive(:bind).and_return(@bind).twice
      @bind.should_receive(:subscribe).and_yield(@message).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      options = {:exchange2 => {:type => :fanout, :name => "exchange2", :options => {:durable => true}}}
      ha_mq.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}, options) {|b, p| p.should == nil}
    end

    it "should subscribe queue to exchange when still connecting" do
      @bind.should_receive(:subscribe).and_yield(@message).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}) {|b, p| p.should == nil}
    end

    it "should subscribe queue to empty exchange if no exchange specified" do
      @queue.should_receive(:subscribe).and_yield(@message).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.subscribe({:name => "queue"}) {|b, p| p.should == nil}
    end

    it "should subscribe queue to exchange in each usable broker" do
      @bind.should_receive(:subscribe).and_yield(@message).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.brokers[0][:status] = :disconnected
      ha_mq.brokers[1][:status] = :connected
      ha_mq.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}) {|b, p| p.should == nil}
    end

    it "should store queues for future reference" do
      @bind.should_receive(:subscribe).and_yield(@message).twice
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"})
      ha_mq.brokers[0][:queues].should == [@queue]
      ha_mq.brokers[1][:queues].should == [@queue]
    end

    it "should ack received message if requested" do
      @info.should_receive(:ack).once
      @bind.should_receive(:subscribe).and_yield(@info, @message).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"},
                      :ack => true) {|b, p| p.should == nil}
    end

    it "should receive message causing it to be unserialized and logged" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Subscribing/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/RECV/).once
      @serializer.should_receive(:load).with(@message).and_return(@packet).once
      @bind.should_receive(:subscribe).and_yield(@message).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"},
                      RightScale::Request => nil) {|b, p| p.class.should == RightScale::Request}
    end

    it "should receive message and log exception if subscribe block fails" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Subscribing/).once
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed executing block/, Exception, :trace).once
      @serializer.should_receive(:load).with(@message).and_return(@packet).once
      @bind.should_receive(:subscribe).and_yield(@message).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"},
                      RightScale::Request => nil) {|b, p| raise Exception}
    end

    it "should return identity of brokers that were subscribed to" do
      @bind.should_receive(:subscribe).and_yield(@message)
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.brokers[0][:status] = :connected
      ha_mq.brokers[1][:status] = :connected
      ids = ha_mq.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}) {|b, p| p.should == nil}
      ids.should == ["rs-broker-first-5672", "rs-broker-second-5672"]
    end

    it "should ignore 'nil' message when using ack" do
      flexmock(RightScale::RightLinkLog).should_receive(:level).and_return(:debug)
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Subscribing/).once
      flexmock(RightScale::RightLinkLog).should_receive(:debug).with(/nil message ignored/).once
      @bind.should_receive(:subscribe).and_yield(@info, "nil").once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      called = 0
      ha_mq.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}, :ack => true) { |b, m| called += 1 }
      called.should == 0
    end

    it "should ignore 'nil' message when not using ack" do
      flexmock(RightScale::RightLinkLog).should_receive(:level).and_return(:debug)
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Subscribing/).once
      flexmock(RightScale::RightLinkLog).should_receive(:debug).with(/nil message ignored/).once
      @bind.should_receive(:subscribe).and_yield("nil").once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      called = 0
      ha_mq.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}) { |b, m| called += 1 }
      called.should == 0
    end

    it "should not unserialize the message if requested" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Subscribing/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV/).never
      @bind.should_receive(:subscribe).and_yield(@message).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}, :no_unserialize => true) do |b, m|
        b.should == "rs-broker-localhost-5672"
        m.should == @message
      end
    end

    it "should log an error if a subscribe fails" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/RECV/).never
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed subscribing/, Exception, :trace).once
      @bind.should_receive(:subscribe).and_raise(Exception)
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"}) {|b, p|}
    end

  end # Subscribing

  describe "Receiving" do

    before(:each) do
      @message = flexmock("message")
      @packet = flexmock("packet", :class => RightScale::Request, :to_s => true, :version => [12, 12]).by_default
      @serializer = flexmock("Serializer")
      @serializer.should_receive(:load).with(@message).and_return(@packet).once.by_default
      @connection = flexmock("connection", :connection_status => true).by_default
      flexmock(AMQP).should_receive(:connect).and_return(@connection).by_default
      @mq = flexmock("mq", :connection => @connection, :return_message => true)
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
      flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    end

    it "should unserialize the message, log it, and return it" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV/).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.__send__(:each_usable) { |b| ha_mq.__send__(:receive, b, "queue", @message, RightScale::Request => nil).should == @packet }
    end

    it "should log a warning if the message is not of the right type and return nil" do
      flexmock(RightScale::RightLinkLog).should_receive(:warn).with(/Received invalid.*packet type/).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.__send__(:each_usable) { |b| ha_mq.__send__(:receive, b, "queue", @message).should == nil }
    end

    it "should show the category in the warning message if specified" do
      flexmock(RightScale::RightLinkLog).should_receive(:warn).with(/Received invalid xxxx packet type/).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.__send__(:each_usable) { |b| ha_mq.__send__(:receive, b, "queue", @message, RightScale::Result => nil, :category => "xxxx") }
    end

    it "should display broker alias in the log" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV b0 /).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.__send__(:each_usable) { |b| ha_mq.__send__(:receive, b, "queue", @message, RightScale::Request => nil) }
    end

    it "should filter the packet display for :info level" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV.*TO YOU/).once
      flexmock(RightScale::RightLinkLog).should_receive(:debug).with(/^RECV.*TO YOU/).never
      @packet.should_receive(:to_s).with([:to], :recv_version).and_return("TO YOU").once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.__send__(:each_usable) { |b| ha_mq.__send__(:receive, b, "queue", @message, RightScale::Request => [:to]) }
    end

    it "should not filter the packet display for :debug level" do
      flexmock(RightScale::RightLinkLog).should_receive(:level).and_return(:debug)
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV.*ALL/).never
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV.*ALL/).once
      @packet.should_receive(:to_s).with(nil, :recv_version).and_return("ALL").once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.__send__(:each_usable) { |b| ha_mq.__send__(:receive, b, "queue", @message, RightScale::Request => [:to]) }
    end

    it "should display additional data in log" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV.*More data/).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.__send__(:each_usable) { |b| ha_mq.__send__(:receive, b, "queue", @message, RightScale::Request => nil, :log_data => "More data") }
    end

    it "should not log a message if requested not to" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV/).never
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.__send__(:each_usable) { |b| ha_mq.__send__(:receive, b, "queue", @message, RightScale::Request => nil, :no_log => true) }
    end

    it "should not log a message if requested not to unless debug level" do
      flexmock(RightScale::RightLinkLog).should_receive(:level).and_return(:debug)
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RECV/).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.__send__(:each_usable) { |b| ha_mq.__send__(:receive, b, "queue", @message, RightScale::Request => nil, :no_log => true) }
    end

    it "should log an error if exception prevents normal logging and should then return nil" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed receiving from queue/, Exception, :trace).once
      @serializer.should_receive(:load).with(@message).and_raise(Exception).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.__send__(:each_usable) { |b| ha_mq.__send__(:receive, b, "queue", @message).should == nil }
    end

    it "should display RE-RECV if the message being received is a retry" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RE-RECV/).once
      @packet.should_receive(:tries).and_return(["try1"]).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.__send__(:each_usable) { |b| ha_mq.__send__(:receive, b, "queue", @message, RightScale::Request => nil).should == @packet }
    end

  end # Receiving

  describe "Unsubscribing" do

    before(:each) do
      @timer = flexmock("timer", :cancel => true).by_default
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).by_default
      @info = flexmock("info", :ack => true).by_default
      @serializer = flexmock("Serializer").by_default
      @direct = flexmock("direct")
      @bind = flexmock("bind", :subscribe => true)
      @queue = flexmock("queue", :bind => @bind, :name => "queue1").by_default
      @connection = flexmock("connection", :connection_status => true).by_default
      flexmock(AMQP).should_receive(:connect).and_return(@connection).by_default
      @mq = flexmock("mq", :queue => @queue, :direct => @direct, :connection => @connection, :return_message => true)
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
      flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    end

    it "should unsubscribe a queue by name" do
      @queue.should_receive(:unsubscribe).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      ha_mq.unsubscribe(["queue1"])
    end

    it "should ignore unsubscribe if queue unknown" do
      @queue.should_receive(:unsubscribe).never
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      ha_mq.unsubscribe(["queue2"])
    end

    it "should yield to supplied block after unsubscribing" do
      @queue.should_receive(:unsubscribe).and_yield.once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      called = 0
      ha_mq.unsubscribe(["queue1"]) { called += 1 }
      called.should == 1
    end

    it "should yield to supplied block if timeout before finish unsubscribing" do
      flexmock(EM::Timer).should_receive(:new).with(10, Proc).and_return(@timer).and_yield.once
      @queue.should_receive(:unsubscribe).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      called = 0
      ha_mq.unsubscribe(["queue1"], 10) { called += 1 }
      called.should == 1
    end

    it "should cancel timer if finish unsubscribing before timer fires" do
      @timer.should_receive(:cancel).once
      flexmock(EM::Timer).should_receive(:new).with(10, Proc).and_return(@timer).once
      @queue.should_receive(:unsubscribe).and_yield.once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      called = 0
      ha_mq.unsubscribe(["queue1"], 10) { called += 1 }
      called.should == 1
    end

    it "should yield to supplied block after unsubscribing even if no queues to unsubscribe" do
      @queue.should_receive(:unsubscribe).never
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      called = 0
      ha_mq.unsubscribe([nil]) { called += 1 }
      called.should == 1
    end

    it "should yield to supplied block once after unsubscribing all queues" do
      @queue.should_receive(:unsubscribe).and_yield.twice
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      called = 0
      ha_mq.unsubscribe(["queue1"]) { called += 1 }
      called.should == 1
    end

    it "should only unsubscribe from usable brokers" do
      @queue.should_receive(:unsubscribe).and_yield.once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.brokers[0][:status] = :failed
      ha_mq.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      called = 0
      ha_mq.unsubscribe(["queue1"]) { called += 1 }
      called.should == 1
    end

    it "should log an error if unsubscribe raises an exception" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed unsubscribing/, Exception, :trace).once
      @queue.should_receive(:unsubscribe).and_raise(Exception).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.subscribe({:name => "queue1"}, {:type => :direct, :name => "exchange"})
      ha_mq.unsubscribe(["queue1"])
    end

  end # Unsubscribing

  describe "Declaring" do

    before(:each) do
      @serializer = flexmock("Serializer")
      @queue = flexmock("queue")
      @connection = flexmock("connection", :connection_status => true).by_default
      flexmock(AMQP).should_receive(:connect).and_return(@connection).by_default
      @mq = flexmock("mq", :connection => @connection, :return_message => true)
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
      flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    end

    it "should declare exchange on all usable brokers" do
      @mq.should_receive(:exchange).twice
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.brokers[0][:status] = :connected
      ha_mq.declare(:exchange, "x", :durable => true)
    end

    it "should declare exchange only on specified brokers" do
      @mq.should_receive(:exchange).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.brokers[0][:status] = :connected
      ha_mq.declare(:exchange, "x", :brokers => ["rs-broker-second-5672"])
    end

    it "should log declaration" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Declaring/).once
      @mq.should_receive(:queue).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.declare(:queue, "q")
    end

    it "should log an error if the declare fails" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Declaring/).once
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed declaring/, Exception, :trace).once
      @mq.should_receive(:queue).and_raise(Exception).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.declare(:queue, "q")
    end

  end # Declaring

  describe "Publishing" do

    before(:each) do
      @message = flexmock("message")
      @packet = flexmock("packet", :class => RightScale::Request, :to_s => true, :version => [12, 12]).by_default
      @serializer = flexmock("Serializer")
      @connection = flexmock("connection", :connection_status => true).by_default
      flexmock(AMQP).should_receive(:connect).and_return(@connection).by_default
      @direct = flexmock("direct")
      @mq = flexmock("mq", :connection => @connection, :return_message => true)
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
      flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    end

    it "should serialize message, publish it, and return list of broker identifiers" do
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", :durable => true).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, :persistent => true).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange", :options => {:durable => true}},
        @packet, :persistent => true).should == ["rs-broker-localhost-5672"]
    end

    it "should publish to first connected broker" do
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, {}).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.brokers[0][:status] = :disconnected
      ha_mq.brokers[1][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange"}, @packet).should == ["rs-broker-second-5672"]
    end

    it "should publish to a randomly selected, connected broker if random requested" do
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, {}).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second, third", :order => :random)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.brokers[1][:status] = :connected
      ha_mq.brokers[2][:status] = :connected
      srand(100)
      ha_mq.publish({:type => :direct, :name => "exchange"}, @packet).should == ["rs-broker-second-5672"]
    end

    it "should publish to all connected brokers if fanout requested" do
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).twice
      @direct.should_receive(:publish).with(@message, :fanout => true).twice
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.brokers[0][:status] = :connected
      ha_mq.brokers[1][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange"}, @packet, :fanout => true).
        should == ["rs-broker-first-5672", "rs-broker-second-5672"]
    end

    it "should publish to first connected broker in selected broker list if requested" do
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, Hash).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second, third")
      ha_mq.brokers[0][:status] = :connected
      ha_mq.brokers[1][:status] = :connected
      ha_mq.brokers[2][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange"}, @packet,
                    :brokers => ["rs-broker-third-5672", "rs-broker-first-5672"]).
        should == ["rs-broker-third-5672"]
    end

    it "should delete the exchange or queue from the AMQP cache if :declare specified" do
      @serializer.should_receive(:dump).with(@packet).and_return(@message)
      @mq.should_receive(:direct).with("exchange", {:declare => true}).and_return(@direct)
      @direct.should_receive(:publish).with(@message, {})
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.brokers[0][:status] = :connected
      ha_mq.brokers[1][:status] = :connected
      exchange = {:type => :direct, :name => "exchange", :options => {:declare => true}}
      flexmock(ha_mq).should_receive(:delete_from_cache).with(any, :direct, "exchange").once
      ha_mq.publish(exchange, @packet)
    end

    it "should log an error if a selected broker is unknown but still publish with any remaining brokers" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Invalid broker id "rs-broker-third-5672"/).once
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, Hash).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first,second")
      ha_mq.brokers[0][:status] = :connected
      ha_mq.brokers[1][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange"}, @packet,
                    :brokers => ["rs-broker-third-5672", "rs-broker-first-5672"]).
        should == ["rs-broker-first-5672"]
    end

    it "should publish to first connected broker in selected broker list if requested even if initialized with random" do
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, Hash).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second, third", :order => :random)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.brokers[1][:status] = :connected
      ha_mq.brokers[2][:status] = :connected
      flexmock(ha_mq).should_receive(:rand).never
      ha_mq.publish({:type => :direct, :name => "exchange"}, @packet,
                    :brokers => ["rs-broker-third-5672", "rs-broker-first-5672"]).
        should == ["rs-broker-third-5672"]
    end

    it "should publish to randomly selected, connected broker in selected broker list if random requested" do
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, Hash).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second, third")
      ha_mq.brokers[0][:status] = :connected
      ha_mq.brokers[1][:status] = :connected
      srand(100)
      ha_mq.publish({:type => :direct, :name => "exchange"}, @packet,
                    :brokers => ["rs-broker-third-5672", "rs-broker-first-5672"],
                    :order => :random).
        should == ["rs-broker-first-5672"]
    end

    it "should log an error if the publish fails" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed publishing/, Exception, :trace).once
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).and_raise(Exception)
      @direct.should_receive(:publish).with(@message, {}).never
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      runner = lambda { ha_mq.publish({:type => :direct, :name => "exchange"}, @packet) }
      runner.should raise_exception(RightScale::HA_MQ::NoConnectedBrokers)
    end

    it "should raise an exception if there are no connected brokers" do
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :disconnected
      runner = lambda { ha_mq.publish({:type => :direct, :name => "exchange"}, @packet) }
      runner.should raise_exception(RightScale::HA_MQ::NoConnectedBrokers)
    end

    it "should not serialize the message if it is already serialized" do
      @serializer.should_receive(:dump).with(@packet).and_return(@message).never
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, :no_serialize => true).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange"}, @message, :no_serialize => true)
    end

    it "should store message info for use by message returns if :mandatory specified" do
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", :durable => true).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, :persistent => true, :mandatory => true).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange", :options => {:durable => true}},
        @packet, :persistent => true, :mandatory => true).should == ["rs-broker-localhost-5672"]
      ha_mq.instance_variable_get(:@published).instance_variable_get(:@cache).size.should == 1
    end

    it "should not store message info for use by message returns if message already serialized" do
      @mq.should_receive(:direct).with("exchange", :durable => true).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, :mandatory => true, :no_serialize => true).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange", :options => {:durable => true}},
        @message, :mandatory => true, :no_serialize => true).should == ["rs-broker-localhost-5672"]
      ha_mq.instance_variable_get(:@published).instance_variable_get(:@cache).size.should == 0
    end

    it "should log that message is being sent with info about which broker used" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND b0/).once
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, {}).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange"}, @packet)
    end

    it "should log broker choices for :debug level" do
      flexmock(RightScale::RightLinkLog).should_receive(:level).and_return(:debug)
      flexmock(RightScale::RightLinkLog).should_receive(:debug).with(/... publish options/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).times(3)
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND b1 \[b1, b2\]/).once
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, {}).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "second:1,first:0,third:2")
      ha_mq.brokers[0][:status] = :connected
      ha_mq.brokers[1][:status] = :disconnected
      ha_mq.brokers[2][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange"}, @packet)
    end

    it "should not log a message if requested not to" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND/).never
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, :no_log => true).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange"}, @packet, :no_log => true)
    end

    it "should not log a message if requested not to unless debug level" do
      flexmock(RightScale::RightLinkLog).should_receive(:level).and_return(:debug)
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND/).once
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, :no_log => true).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange"}, @packet, :no_log => true)
    end

    it "should display broker alias in the log" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND b0 /).once
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, {}).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange"}, @packet)
    end

    it "should filter the packet display for :info level" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND.*TO YOU/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND.*TO YOU/).never
      @packet.should_receive(:to_s).with([:to], :send_version).and_return("TO YOU").once
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, :log_filter => [:to]).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange"}, @packet, :log_filter => [:to])
    end

    it "should not filter the packet display for :debug level" do
      flexmock(RightScale::RightLinkLog).should_receive(:level).and_return(:debug)
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND.*ALL/).never
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND.*ALL/).once
      @packet.should_receive(:to_s).with(nil, :send_version).and_return("ALL").once
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, :log_filter => [:to]).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange"}, @packet, :log_filter => [:to])
    end
    
    it "should display additional data in log" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^SEND.*More data/).once
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, :log_data => "More data").once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange"}, @packet, :log_data => "More data")
    end

    it "should display RE-SEND if the message being sent is a retry" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/^RE-SEND/).once
      @packet = flexmock("packet", :class => RightScale::Request, :to_s => true, :tries => ["try1"], :version => [12, 12])
      @serializer.should_receive(:dump).with(@packet).and_return(@message).once
      @mq.should_receive(:direct).with("exchange", {}).and_return(@direct).once
      @direct.should_receive(:publish).with(@message, {}).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.brokers[0][:status] = :connected
      ha_mq.publish({:type => :direct, :name => "exchange"}, @packet)
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
      flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
      flexmock(RightScale::RightLinkLog).should_receive(:error).never.by_default
      @message = flexmock("message")
      @packet = flexmock("packet", :class => RightScale::Request, :to_s => true, :version => [12, 12]).by_default
      @info = flexmock("info", :reply_text => "NO_CONSUMERS", :exchange => "exchange", :routing_key => "routing_key").by_default
      @serializer = flexmock("Serializer")
      @serializer.should_receive(:load).with(@message).and_return(@packet).by_default
      @connection = flexmock("connection", :connection_status => true).by_default
      flexmock(AMQP).should_receive(:connect).and_return(@connection).by_default
      @direct = flexmock("direct")
      @mq = flexmock("mq", :connection => @connection).by_default
      @mq.should_receive(:return_message).by_default
    end

    it "should register return message block with each usable broker replacing the default handler" do
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
      @mq.should_receive(:return_message).twice.by_default
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      @mq.should_receive(:return_message).twice
      ha_mq.return_message { |_, _, _, _| }
    end

    it "should invoke block and log the return" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting to broker/).once
      flexmock(RightScale::RightLinkLog).should_receive(:debug).with(/RETURN/).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      called = 0
      ha_mq.return_message do |id, reason, msg, to|
        called += 1
        id.should == "rs-broker-localhost-5672"
        reason.should == "NO_CONSUMERS"
        msg.should == @message
        to.should == "exchange"
      end
      ha_mq.brokers[0][:mq].on_return_message.call(@info, @message)
      called.should == 1
    end

    it "should invoke block with routing key if exchange is empty" do
      ha_mq = RightScale::HA_MQ.new(@serializer)
      called = 0
      ha_mq.return_message do |id, reason, msg, to|
        called += 1
        id.should == "rs-broker-localhost-5672"
        reason.should == "NO_CONSUMERS"
        msg.should == @message
        to.should == "routing_key"
      end
      @info.should_receive(:exchange).and_return("")
      ha_mq.brokers[0][:mq].on_return_message.call(@info, @message)
      called.should == 1
    end

    it "should log an error if there is a failure while processing the return" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed return/, Exception, :trace).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      called = 0
      ha_mq.return_message do |id, reason, msg, to|
        called += 1
        raise Exception
      end
      ha_mq.brokers[0][:mq].on_return_message.call(@info, @message)
      called.should == 1
    end

    describe "when non-delivery" do

      it "should store non-delivery block for use by return handler" do
        ha_mq = RightScale::HA_MQ.new(@serializer)
        non_delivery = lambda {}
        ha_mq.non_delivery(&non_delivery)
        ha_mq.instance_variable_get(:@non_delivery).should == non_delivery
      end

    end

    describe "when handling return" do

      it "should republish using broker not yet tried if possible" do
        ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first,second")
        ha_mq.brokers[0][:status] = :connected
        ha_mq.brokers[1][:status] = :connected
        options = {}
        message = flexmock("message")
        remaining = [ha_mq.brokers[1][:identity]]
        flexmock(ha_mq).should_receive(:publish).with(hsh(:name => "to"), message,
                hsh(:no_serialize => true, :brokers => remaining, :persistent => nil, :mandatory => true)).once
        failed = [ha_mq.brokers[0][:identity]]
        details = {:type => "/foo/bar", :options => options, :brokers => ha_mq.connected, :failed => failed}
        ha_mq.handle_return("identity", "reason", message, "to", details)
      end

      it "should use details about previous attempts if available" do

      end

      it "should republish to same broker without mandatory if message is persistent and no other brokers available" do
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/setup/).twice
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/RE-ROUTE/).once
        ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first,second")
        ha_mq.brokers[0][:status] = :connected
        ha_mq.brokers[1][:status] = :disconnected
        options = {:persistent => true}
        message = flexmock("message")
        remaining = [ha_mq.brokers[0][:identity]]
        flexmock(ha_mq).should_receive(:publish).with(hsh(:name => "to"), message,
                hsh(:no_serialize => true, :brokers => remaining, :persistent => true, :mandatory => false)).once
        failed = [ha_mq.brokers[0][:identity]]
        details = {:type => "/foo/bar", :options => options, :brokers => ha_mq.connected, :failed => failed}
        ha_mq.handle_return("identity", "NO_CONSUMERS", message, "to", details)
      end

      it "should republish to same broker without mandatory if message is one-way and no other brokers available" do
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/setup/).twice
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/RE-ROUTE/).once
        ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first,second")
        ha_mq.brokers[0][:status] = :connected
        ha_mq.brokers[1][:status] = :disconnected
        message = flexmock("message")
        remaining = [ha_mq.brokers[0][:identity]]
        flexmock(ha_mq).should_receive(:publish).with(hsh(:name => "to"), message,
                hsh(:no_serialize => true, :brokers => remaining, :persistent => nil, :mandatory => false)).once
        failed = [ha_mq.brokers[0][:identity]]
        details = {:type => "/foo/bar", :one_way => true, :options => options, :brokers => ha_mq.connected, :failed => failed}
        ha_mq.handle_return("identity", "NO_CONSUMERS", message, "to", details)
      end

      it "should log info and make non-delivery call even if persistent when returned because of no queue" do
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/setup/).twice
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/NO ROUTE/).once
        ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first,second")
        ha_mq.brokers[0][:status] = :connected
        ha_mq.brokers[1][:status] = :disconnected
        called = 0
        ha_mq.non_delivery { |type, token, from, to| called += 1 }
        options = {:persistent => true}
        message = flexmock("message")
        flexmock(ha_mq).should_receive(:publish).never
        failed = [ha_mq.brokers[0][:identity]]
        details = {:type => "/foo/bar", :options => options, :brokers => ha_mq.connected, :failed => failed}
        ha_mq.handle_return("identity", "no queue", message, "to", details)
        called.should == 1
      end

      it "should log info and make non-delivery call if no route can be found" do
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/setup/).twice
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/NO ROUTE/).once
        ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first,second")
        ha_mq.brokers[0][:status] = :connected
        ha_mq.brokers[1][:status] = :disconnected
        called = 0
        ha_mq.non_delivery { |type, token, from, to| called += 1 }
        options = {}
        message = flexmock("message")
        flexmock(ha_mq).should_receive(:publish).never
        failed = [ha_mq.brokers[0][:identity]]
        details = {:type => "/foo/bar", :options => options, :brokers => ha_mq.connected, :failed => failed}
        ha_mq.handle_return("identity", "any reason", message, "to", details)
        called.should == 1
      end

    end

  end # Returning

  describe "Deleting" do

    before(:each) do
      @serializer = flexmock("Serializer")
      @connection = flexmock("connection", :connection_status => true).by_default
      flexmock(AMQP).should_receive(:connect).and_return(@connection).by_default
      @queue = flexmock("queue")
      @mq = flexmock("mq", :connection => @connection, :return_message => true).by_default
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
      flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    end

    it "should delete queue in each usable broker" do
      @queue.should_receive(:delete).once
      @mq.should_receive(:queue).with("queue", {}).and_return(@queue).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.brokers[0][:status] = :disconnected
      ha_mq.delete("queue").should == ["rs-broker-second-5672"]
    end

    it "should log an error if a delete fails for a broker" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed deleting/, Exception, :trace).once
      @mq.should_receive(:queue).and_raise(Exception)
      ha_mq = RightScale::HA_MQ.new(@serializer)
      ha_mq.delete("queue").should == []
    end

  end # Deleting

  describe "Connecting" do

    before(:each) do
      @serializer = flexmock("Serializer")
      @connection = flexmock("connection", :connection_status => true).by_default
      flexmock(AMQP).should_receive(:connect).and_return(@connection).by_default
      @mq = flexmock("mq", :connection => @connection, :return_message => true)
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
      flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    end

    it "should connect and add a new broker to the end of the list" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first")
      ha_mq.status.should == [{:alias => "b0", :identity => "rs-broker-first-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0}]
      res = ha_mq.connect("second", 5673, 1)
      res.should be_true
      ha_mq.status.should == [{:alias => "b0", :identity => "rs-broker-first-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0},
                              {:alias => "b1", :identity => "rs-broker-second-5673", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0}]
    end

    it "should reconnect an existing broker if it is not connected" do
      flexmock(AMQP).should_receive(:connect).and_return(@connection).times(3)
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.status.should == [{:alias => "b0", :identity => "rs-broker-first-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0},
                              {:alias => "b1", :identity => "rs-broker-second-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0}]
      ha_mq.brokers[0][:status] = :failed
      ha_mq.brokers[1][:status] = :connected
      res = ha_mq.connect("first", 5672, 0)
      res.should be_true
      ha_mq.status.should == [{:alias => "b0", :identity => "rs-broker-first-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0},
                              {:alias => "b1", :identity => "rs-broker-second-5672", :status => :connected,
                               :disconnects => 0, :failures => 0, :retries => 0}]
    end

    it "should not do anything except log a message if asked to reconnect an already connected broker" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting to/).twice
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Ignored request to reconnect/).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.brokers[1][:status] = :connected
      res = ha_mq.connect("second", 5672, 1)
      res.should be_false
      ha_mq.status.should == [{:alias => "b0", :identity => "rs-broker-first-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0},
                              {:alias => "b1", :identity => "rs-broker-second-5672", :status => :connected,
                               :disconnects => 0, :failures => 0, :retries => 0}]
    end

    it "should not do anything except log a message if asked to reconnect a broker that is currently being connected" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting to/).twice
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Ignored request to reconnect/).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      res = ha_mq.connect("second", 5672, 1)
      res.should be_false
      ha_mq.status.should == [{:alias => "b0", :identity => "rs-broker-first-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0},
                              {:alias => "b1", :identity => "rs-broker-second-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0}]
    end

    it "should reconnect already connected broker if force specified" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting to/).times(3)
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Ignored request to reconnect/).never
      @connection.should_receive(:close).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.brokers[1][:status] = :connected
      res = ha_mq.connect("second", 5672, 1, nil, force = true)
      res.should be_true
      ha_mq.status.should == [{:alias => "b0", :identity => "rs-broker-first-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0},
                              {:alias => "b1", :identity => "rs-broker-second-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0}]
    end

    it "should slot broker into specified priority position when at end of list" do
      flexmock(AMQP).should_receive(:connect).and_return(@connection).times(3)
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      res = ha_mq.connect("third", 5672, 2, 2)
      res.should be_true
      ha_mq.status.should == [{:alias => "b0", :identity => "rs-broker-first-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0},
                              {:alias => "b1", :identity => "rs-broker-second-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0},
                              {:alias => "b2", :identity => "rs-broker-third-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0}]
    end

    it "should slot broker into specified priority position when already is a broker in that position" do
      flexmock(AMQP).should_receive(:connect).and_return(@connection).times(3)
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      res = ha_mq.connect("third", 5672, 2, 1)
      res.should be_true
      ha_mq.status.should == [{:alias => "b0", :identity => "rs-broker-first-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0},
                              {:alias => "b2", :identity => "rs-broker-third-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0},
                              {:alias => "b1", :identity => "rs-broker-second-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0}]
    end

    it "should yield to the block provided with the newly connected broker identity" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first")
      identity = nil
      res = ha_mq.connect("second", 5673, 1) { |i| identity = i }
      res.should be_true
      identity.should == "rs-broker-second-5673"
    end

    it "should raise an exception if try to change host and port of an existing broker" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      runner = lambda { ha_mq.connect("third", 5672, 0) }
      runner.should raise_exception(Exception, /Not allowed to change host or port/)
    end

    it "should raise an exception and close connection if specified priority position leaves a gap in the list" do
      @connection.should_receive(:close).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      runner = lambda { ha_mq.connect("third", 5672, 2, 3) }
      runner.should raise_exception(Exception, /Requested priority position/)
    end

  end # Connecting

  describe "Removing" do

    before(:each) do
      @connection = flexmock("connection", :connection_status => true).by_default
      flexmock(AMQP).should_receive(:connect).and_return(@connection).by_default
      @mq = flexmock("mq", :connection => @connection, :return_message => true)
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
      flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    end

    it "should remove broker after disconnecting and pass identity to block" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting to/).times(3)
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Removing/).once
      @connection.should_receive(:close).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second, third")
      identity = nil
      res = ha_mq.remove("second", 5672) { |i| identity = i }
      res.should == "rs-broker-second-5672"
      identity.should == "rs-broker-second-5672"
      ha_mq.get("rs-broker-second-5672").should be_nil
      ha_mq.get("rs-broker-first-5672").should_not be_nil
      ha_mq.get("rs-broker-third-5672").should_not be_nil
      ha_mq.brokers.size.should == 2
    end

    it "should remove last broker if requested" do
      @connection.should_receive(:close).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first")
      identity = nil
      res = ha_mq.remove("first", 5672) { |i| identity = i }
      res.should == "rs-broker-first-5672"
      identity.should == "rs-broker-first-5672"
      ha_mq.get("rs-broker-first-5672").should be_nil
      ha_mq.brokers.size.should == 0
    end

    it "should remove broker when no block supplied but still return a result" do
      @connection.should_receive(:close).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first")
      res = ha_mq.remove("first", 5672)
      res.should == "rs-broker-first-5672"
      ha_mq.get("rs-broker-first-5672").should be_nil
      ha_mq.brokers.size.should == 0
    end

    it "should return nil and not execute block if broker is unknown" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Connecting to/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Ignored request to remove/).once
      @connection.should_receive(:close).never
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first")
      identity = nil
      res = ha_mq.remove("second", 5672) { |i| identity = i }
      res.should be_nil
      identity.should be_nil
      ha_mq.get("rs-broker-first-5672").should_not be_nil
      ha_mq.brokers.size.should == 1
    end

    it "should invoke connection status callback updates only if connection not already disabled" do
      @connection.should_receive(:close).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second, third")
      ha_mq.brokers[0][:status] = :connected
      ha_mq.brokers[1][:status] = :failed
      ha_mq.brokers[2][:status] = :connected
      flexmock(ha_mq).should_receive(:update_status).once
      res = ha_mq.remove("first", 5672)
      res = ha_mq.remove("second", 5672)
    end

    it "should close connection and mark as failed when told broker is not usable" do
      @connection.should_receive(:close).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.brokers[0][:status] = :connected
      ha_mq.brokers[1][:status] = :connected
      res = ha_mq.declare_unusable(["rs-broker-first-5672"])
      ha_mq.brokers[0][:status].should == :failed
    end

  end

  describe "Monitoring" do

    include RightScale::StatsHelper

    before(:each) do
      @timer = flexmock("timer")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).by_default
      @timer.should_receive(:cancel).by_default
      @info = flexmock("info", :ack => true).by_default
      @message = flexmock("message")
      @packet = flexmock("packet", :class => RightScale::Request, :to_s => true, :version => [12, 12]).by_default
      @serializer = flexmock("Serializer", :load => @packet).by_default
      @direct = flexmock("direct")
      @bind = flexmock("bind")
      @bind.should_receive(:subscribe).and_yield(@message)
      @queue = flexmock("queue", :bind => @bind)
      @connection = flexmock("connection", :connection_status => true).by_default
      flexmock(AMQP).should_receive(:connect).and_return(@connection).by_default
      @mq = flexmock("mq", :queue => @queue, :direct => @direct, :connection => @connection, :return_message => true)
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
      flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    end

    it "should give access to or list usable brokers" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      aliases = []
      res = ha_mq.__send__(:each_usable) { |b| aliases << b[:alias] }
      aliases.should == ["b0", "b1"]
      res.size.should == 2
      res[0][:alias].should == "b0"
      res[1][:alias].should == "b1"

      ha_mq.brokers[1][:status] = :connected
      aliases = []
      res = ha_mq.__send__(:each_usable) { |b| aliases << b[:alias] }
      aliases.should == ["b0", "b1"]
      res.size.should == 2
      res[0][:alias].should == "b0"
      res[1][:alias].should == "b1"

      ha_mq.brokers[0][:status] = :connected
      aliases = []
      res = ha_mq.__send__(:each_usable) { |b| aliases << b[:alias] }
      aliases.should == ["b0", "b1"]
      res.size.should == 2
      res[0][:alias].should == "b0"
      res[1][:alias].should == "b1"

      ha_mq.brokers[0][:status] = :disconnected
      aliases = []
      res = ha_mq.__send__(:each_usable) { |b| aliases << b[:alias] }
      aliases.should == ["b1"]
      res.size.should == 1
      res[0][:alias].should == "b1"

      ha_mq.brokers[0][:status] = :failed
      aliases = []
      res = ha_mq.__send__(:each_usable) { |b| aliases << b[:alias] }
      aliases.should == ["b1"]
      res.size.should == 1
      res[0][:alias].should == "b1"

      ha_mq.brokers[1][:status] = :closed
      aliases = []
      res = ha_mq.__send__(:each_usable) { |b| aliases << b[:alias] }
      aliases.should == []
      res.size.should == 0

      ha_mq.brokers[1][:status] = :connecting
      aliases = []
      res = ha_mq.__send__(:each_usable) { |b| aliases << b[:alias] }
      aliases.should == ["b1"]
      res.size.should == 1
      res[0][:alias].should == "b1"
      ha_mq.usable.should == ["rs-broker-second-5672"]

      ha_mq.brokers[0][:status] = :connected
      aliases = []
      res = ha_mq.__send__(:each_usable) { |b| aliases << b[:alias] }
      aliases.should == ["b0", "b1"]
      res.size.should == 2
      res[0][:alias].should == "b0"
      res[1][:alias].should == "b1"

      res = ha_mq.__send__(:each_usable)
      res.size.should == 2
      res[0][:alias].should == "b0"
      res[1][:alias].should == "b1"
      ha_mq.usable.should == ["rs-broker-first-5672", "rs-broker-second-5672"]
    end

    it "should give list of unusable brokers" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.brokers[1][:status] = :connecting
      res = ha_mq.unusable
      res.should == []

      ha_mq.brokers[0][:status] = :failed
      res = ha_mq.unusable
      res.should == ["rs-broker-first-5672"]

      ha_mq.brokers[1][:status] = :closed
      res = ha_mq.unusable
      res.should == ["rs-broker-first-5672", "rs-broker-second-5672"]
    end

    it "should give access to each selected usable broker" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second, third")
      ha_mq.brokers[1][:status] = :connected
      ha_mq.brokers[2][:status] = :disconnected
      aliases = []
      res = ha_mq.__send__(:each_usable, ["rs-broker-second-5672", "rs-broker-third-5672"]) { |b| aliases << b[:alias] }
      aliases.should == ["b1"]
      res.size.should == 1
      res[0][:alias].should == "b1"
    end

    it "should tell whether a broker is connected" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.connected?("rs-broker-first-5672").should be_false
      ha_mq.brokers[1][:status] = :connected
      ha_mq.connected?("rs-broker-second-5672").should be_true
      ha_mq.connected?("rs-broker-third-5672").should be_nil
    end

    it "should give list of connected brokers" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.connected.should == []
      ha_mq.brokers[1][:status] = :connected
      ha_mq.connected.should == ["rs-broker-second-5672"]
      ha_mq.brokers[0][:status] = :connected
      ha_mq.connected.should == ["rs-broker-first-5672", "rs-broker-second-5672"]
      ha_mq.brokers[1][:status] = :disconnected
      ha_mq.connected.should == ["rs-broker-first-5672"]
    end

    it "should give list of all brokers" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.all.should == ["rs-broker-first-5672", "rs-broker-second-5672"]
      ha_mq.brokers[0][:status] = :failed
      ha_mq.brokers[1][:status] = :disconnected
      ha_mq.all.should == ["rs-broker-first-5672", "rs-broker-second-5672"]
    end

    it "should give list of failed brokers" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.failed.should == []
      ha_mq.brokers[1][:status] = :connected
      ha_mq.failed.should == []
      ha_mq.brokers[0][:status] = :failed
      ha_mq.failed.should == ["rs-broker-first-5672"]
      ha_mq.brokers[1][:status] = :failed
      ha_mq.failed.should == ["rs-broker-first-5672", "rs-broker-second-5672"]
      ha_mq.brokers[0][:status] = :disconnected
      ha_mq.failed.should == ["rs-broker-second-5672"]
    end

    it "should give list of failed brokers with exponential backoff if have repeated failures" do
      @connection.should_receive(:close)
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      flexmock(AMQP).should_receive(:connect).and_raise(Exception)
      ha_mq.brokers[1][:status] = :failed
      40.times do |i|
        failed = ha_mq.failed(backoff = true)
        failed.should == if [0,1,3,7,15,27,39].include?(i) then ["rs-broker-second-5672"] else [] end
        ha_mq.connect("second", 5672, 1) unless failed.empty?
      end
    end

    it "should give list of failed brokers with exponential backoff if have repeated failures reported via callback" do
      @connection.should_receive(:close)
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      flexmock(AMQP).should_receive(:connect).and_return(@connection)
      ha_mq.brokers[1][:status] = :failed
      40.times do |i|
        failed = ha_mq.failed(backoff = true)
        failed.should == if [0,1,3,7,15,27,39].include?(i) then ["rs-broker-second-5672"] else [] end
        unless failed.empty?
          ha_mq.connect("second", 5672, 1)
          ha_mq.__send__(:update_status, ha_mq.brokers[1], :failed)
        end
      end
    end

    it "should give broker status list" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.status.should == [{:alias => "b0", :identity => "rs-broker-first-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0},
                              {:alias => "b1", :identity => "rs-broker-second-5672", :status => :connecting,
                               :disconnects => 0, :failures => 0, :retries => 0}]
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :failed)
      ha_mq.__send__(:update_status, ha_mq.brokers[1], :ready)
      ha_mq.brokers[1][:status] = :connected
      ha_mq.status.should == [{:alias => "b0", :identity => "rs-broker-first-5672", :status => :failed,
                               :disconnects => 0, :failures => 1, :retries => 0},
                              {:alias => "b1", :identity => "rs-broker-second-5672", :status => :connected,
                               :disconnects => 0, :failures => 0, :retries => 0}]
    end

    it "should give broker statistics" do
      flexmock(Time).should_receive(:now).and_return(1000000).by_default
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second, third")
      ha_mq.stats.should == {"brokers" => [{"alias" => "b0", "identity" => "rs-broker-first-5672",
                                            "status" => "connecting", "disconnects" => nil, "disconnect last" => nil,
                                            "failures" => nil, "failure last" => nil, "retries" => nil},
                                           {"alias" => "b1", "identity" => "rs-broker-second-5672",
                                            "status" => "connecting", "disconnects" => nil, "disconnect last" => nil,
                                            "failures" => nil, "failure last" => nil, "retries" => nil},
                                           {"alias" => "b2", "identity" => "rs-broker-third-5672",
                                            "status" => "connecting", "disconnects" => nil, "disconnect last" => nil,
                                            "failures" => nil, "failure last" => nil, "retries" => nil}],
                             "exceptions" => nil,
                             "returns" => nil}
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :ready)
      ha_mq.__send__(:update_status, ha_mq.brokers[1], :disconnected)
      ha_mq.__send__(:update_status, ha_mq.brokers[2], :failed)
      flexmock(Time).should_receive(:now).and_return(1000100)
      ha_mq.stats.should == {"brokers" => [{"alias" => "b0", "identity" => "rs-broker-first-5672",
                                            "status" => "connected", "disconnects" => nil, "disconnect last" => nil,
                                            "failures" => nil, "failure last" => nil, "retries" => nil},
                                           {"alias" => "b1", "identity" => "rs-broker-second-5672",
                                            "status" => "disconnected", "disconnects" => 1, "disconnect last" => {"elapsed" => 100},
                                            "failures" => nil, "failure last" => nil, "retries" => nil},
                                           {"alias" => "b2", "identity" => "rs-broker-third-5672",
                                            "status" => "failed", "disconnects" => nil, "disconnect last" => nil,
                                            "failures" => 1, "failure last" => {"elapsed" => 100}, "retries" => nil}],
                             "exceptions" => nil,
                             "returns" => nil}
    end

    it "should provide connection status callback when cross 0/1 connection boundary" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      connected = 0
      disconnected = 0
      ha_mq.connection_status do |status|
        if status == :connected
          (ha_mq.brokers[0][:status] == :connected ||
           ha_mq.brokers[1][:status] == :connected).should be_true
          connected += 1
        elsif status == :disconnected
          (ha_mq.brokers[0][:status] == :disconnected &&
           ha_mq.brokers[1][:status] == :disconnected).should be_true
          disconnected += 1
        end
      end
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :ready)
      connected.should == 1
      disconnected.should == 0
      ha_mq.__send__(:update_status, ha_mq.brokers[1], :ready)
      connected.should == 1
      disconnected.should == 0
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :disconnected)
      connected.should == 1
      disconnected.should == 0
      ha_mq.__send__(:update_status, ha_mq.brokers[1], :disconnected)
      connected.should == 1
      disconnected.should == 1
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :ready)
      connected.should == 2
      disconnected.should == 1
      ha_mq.__send__(:update_status, ha_mq.brokers[1], :ready)
      connected.should == 2
      disconnected.should == 1
    end

    it "should provide connection status callback when cross n/n-1 connection boundary when all specified" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      connected = 0
      disconnected = 0
      ha_mq.connection_status(:boundary => :all) do |status|
        if status == :connected
          (ha_mq.brokers[0][:status] == :connected &&
           ha_mq.brokers[1][:status] == :connected).should be_true
          connected += 1
        elsif status == :disconnected
          (ha_mq.brokers[0][:status] == :disconnected ||
           ha_mq.brokers[1][:status] == :disconnected).should be_true
          disconnected += 1
        end
      end
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :ready)
      connected.should == 0
      disconnected.should == 0
      ha_mq.__send__(:update_status, ha_mq.brokers[1], :ready)
      connected.should == 1
      disconnected.should == 0
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :disconnected)
      connected.should == 1
      disconnected.should == 1
      ha_mq.__send__(:update_status, ha_mq.brokers[1], :disconnected)
      connected.should == 1
      disconnected.should == 1
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :ready)
      connected.should == 1
      disconnected.should == 1
      ha_mq.__send__(:update_status, ha_mq.brokers[1], :ready)
      connected.should == 2
      disconnected.should == 1
    end

    it "should provide connection status callback for specific broker set" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second, third")
      connected = 0
      disconnected = 0
      ha_mq.connection_status(:brokers => ["rs-broker-first-5672", "rs-broker-third-5672"]) do |status|
        if status == :connected
          (ha_mq.brokers[0][:status] == :connected ||
           ha_mq.brokers[2][:status] == :connected).should be_true
          connected += 1
        elsif status == :disconnected
          (ha_mq.brokers[0][:status] == :disconnected &&
           ha_mq.brokers[2][:status] == :disconnected).should be_true
          disconnected += 1
        end
      end
      ha_mq.__send__(:update_status, ha_mq.brokers[1], :ready)
      connected.should == 0
      disconnected.should == 0
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :ready)
      connected.should == 1
      disconnected.should == 0
      ha_mq.__send__(:update_status, ha_mq.brokers[2], :ready)
      connected.should == 1
      disconnected.should == 0
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :disconnected)
      connected.should == 1
      disconnected.should == 0
      ha_mq.__send__(:update_status, ha_mq.brokers[1], :disconnected)
      connected.should == 1
      disconnected.should == 0
      ha_mq.__send__(:update_status, ha_mq.brokers[2], :disconnected)
      connected.should == 1
      disconnected.should == 1
      ha_mq.__send__(:update_status, ha_mq.brokers[2], :ready)
      connected.should == 2
      disconnected.should == 1
    end

    it "should provide connection status callback only once when one-off is requested" do
      ha_mq = RightScale::HA_MQ.new(@serializer)
      called = 0
      ha_mq.connection_status(:one_off => 10) { |_| called += 1 }
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :ready)
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :disconnected)
      called.should == 1
      called = 0
      ha_mq.connection_status { |_| called += 1 }
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :ready)
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :disconnected)
      called.should == 2
    end

    it "should use connection status timer when one-off is requested" do
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).once
      @timer.should_receive(:cancel).once
      ha_mq = RightScale::HA_MQ.new(@serializer)
      called = 0
      ha_mq.connection_status(:one_off => 10) { |_| called += 1 }
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :ready)
      called.should == 1
    end

    it "should use give timeout connection status if one-off request times out" do
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).and_yield.once
      @timer.should_receive(:cancel).never
      ha_mq = RightScale::HA_MQ.new(@serializer)
      called = 0
      ha_mq.connection_status(:one_off => 10) { |status| called += 1; status.should == :timeout }
      called.should == 1
    end

    it "should log an error when status indicates that failed to connect" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed to connect/).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "host")
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :failed)
    end

    it "should return identity of connected brokers" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.brokers[1][:status] = :connected
      ha_mq.connected.should == ["rs-broker-second-5672"]
      ha_mq.brokers[0][:status] = :connected
      ha_mq.connected.should == ["rs-broker-first-5672", "rs-broker-second-5672"]
      ha_mq.brokers[0][:status] = :disconnected
      ha_mq.connected.should == ["rs-broker-second-5672"]
      ha_mq.brokers[1][:status] = :closed
      ha_mq.connected.should == []
    end

    it "should be able to have multiple connection status callbacks" do
      ha_mq = RightScale::HA_MQ.new(@serializer)
      called1 = 0
      called2 = 0
      ha_mq.connection_status(:one_off => 10) { |_| called1 += 1 }
      ha_mq.connection_status(:boundary => :all) { |_| called2 += 1 }
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :ready)
      ha_mq.__send__(:update_status, ha_mq.brokers[0], :disconnected)
      called1.should == 1
      called2.should == 2
    end

  end # Monitoring

  describe "Closing" do

    before(:each) do
      @serializer = flexmock("Serializer")
      @connection = flexmock("connection", :connection_status => true).by_default
      flexmock(AMQP).should_receive(:connect).and_return(@connection).by_default
      @mq = flexmock("mq", :connection => @connection, :instance_variable_get => @connection, :return_message => true)
      flexmock(MQ).should_receive(:new).with(@connection).and_return(@mq).by_default
      flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    end

    it "should close all broker connections and execute block after all connections are closed" do
      @connection.should_receive(:close).and_yield.twice
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.brokers[0][:status].should == :connecting; ha_mq.brokers[1][:status].should == :connecting
      called = false
      ha_mq.close { called = true; ha_mq.brokers[0][:status].should == :closed; ha_mq.brokers[1][:status].should == :closed }
      called.should be_true
    end

    it "should close broker connections when no block supplied" do
      @connection.should_receive(:close).twice
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.close
    end

    it "should close all broker connections even if encounter an exception" do
      @connection.should_receive(:close).and_raise(Exception).twice
      flexmock(RightScale::RightLinkLog).should_receive(:error).twice
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      ha_mq.close
      ha_mq.brokers[0][:status].should == :closed; ha_mq.brokers[1][:status].should == :closed
    end

    it "should close an individual broker connection" do
      @connection.should_receive(:close).once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      flexmock(ha_mq).should_receive(:update_status).once
      ha_mq.close_one("rs-broker-first-5672")
    end

    it "should close an individual broker connection and execute block if given" do
      @connection.should_receive(:close).and_yield.once
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second")
      flexmock(ha_mq).should_receive(:update_status).once
      called = false
      ha_mq.close_one("rs-broker-first-5672") { called = true; ha_mq.brokers[0][:status].should == :closed }
      called.should be_true
    end

    it "should propagate connection status callback updates only if connection not already disabled" do
      @connection.should_receive(:close).twice
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second, third")
      ha_mq.brokers[0][:status] = :connected
      ha_mq.brokers[1][:status] = :failed
      ha_mq.brokers[2][:status] = :connected
      flexmock(ha_mq).should_receive(:update_status).once
      res = ha_mq.close_one("rs-broker-first-5672")
      res = ha_mq.close_one("rs-broker-second-5672")
      res = ha_mq.close_one("rs-broker-third-5672", propagate = false)
    end

    it "should change failed status to closed" do
      @connection.should_receive(:close).never
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first, second, third")
      ha_mq.brokers[1][:status] = :failed
      res = ha_mq.close_one("rs-broker-second-5672")
      ha_mq.brokers[1][:status].should == :closed
    end

    it "should raise exception if unknown broker" do
      ha_mq = RightScale::HA_MQ.new(@serializer, :host => "first")
      runner = lambda { ha_mq.close_one("rs-broker-second-5672") }
      runner.should raise_exception(Exception, /Cannot close unknown broker/)
    end

  end # Closing

end # RightScale::HA_MQ
