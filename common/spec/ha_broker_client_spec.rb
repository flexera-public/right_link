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

describe RightScale::HABrokerClient do

  include FlexMock::ArgumentTypes

  before(:each) do
    flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    flexmock(RightScale::RightLinkLog).should_receive(:error).never.by_default
#   flexmock(RightScale::RightLinkLog).should_receive(:error).with(on { |arg| puts caller.join("\n") } )
    flexmock(RightScale::RightLinkLog).should_receive(:warning).never.by_default
  end

  describe "Context" do

    before(:each) do
      @packet1 = flexmock("packet1", :class => RightScale::Request, :name => "request", :type => "type1",
                          :from => "from1", :token => "token1", :one_way => false)
      @packet2 = flexmock("packet2", :class => FlexMock, :name => "flexmock")
      @brokers = ["broker"]
      @options = {:option => "option"}
    end

    it "should initialize context" do
      context = RightScale::HABrokerClient::Context.new(@packet1, @options, @brokers)
      context.name.should == "request"
      context.type.should == "type1"
      context.from.should == "from1"
      context.token.should == "token1"
      context.one_way.should be_false
      context.options.should == @options
      context.brokers.should == @brokers
      context.failed.should == []
    end

    it "should treat type, from, token, and one_way as optional members of packet but default one_way to true" do
      context = RightScale::HABrokerClient::Context.new(@packet2, @options, @brokers)
      context.name.should == "flexmock"
      context.type.should be_nil
      context.from.should be_nil
      context.token.should be_nil
      context.one_way.should be_true
      context.options.should == @options
      context.brokers.should == @brokers
      context.failed.should == []
    end

  end

  describe "Caching" do

    before(:each) do
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
      @published = RightScale::HABrokerClient::Published.new
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
      @context1 = RightScale::HABrokerClient::Context.new(@packet1, @options, @brokers)
      @context2 = RightScale::HABrokerClient::Context.new(@packet2, @options, @brokers)
      @context3 = RightScale::HABrokerClient::Context.new(@packet3, @options, @brokers)
    end

    it "should use message signature as cache hash key if it has one" do
      @published.identify(@message1).should == @key1
      @published.identify(@message2).should == @key2
      @published.identify(@message3).should == @key3
    end

    it "should store message info" do
      @published.store(@message1, @context1)
      @published.instance_variable_get(:@cache)[@key1].should == [1000000, @context1]
      @published.instance_variable_get(:@lru).should == [@key1]
    end

    it "should update timestamp and lru list when store to existing entry" do
      @published.store(@message1, @context1)
      @published.instance_variable_get(:@cache)[@key1].should == [1000000, @context1]
      @published.instance_variable_get(:@lru).should == [@key1]
      @published.store(@message2, @context2)
      @published.instance_variable_get(:@lru).should == [@key1, @key2]
      flexmock(Time).should_receive(:now).and_return(Time.at(1000010))
      @published.store(@message1, @context1)
      @published.instance_variable_get(:@cache)[@key1].should == [1000010, @context1]
      @published.instance_variable_get(:@lru).should == [@key2, @key1]
    end

    it "should remove old cache entries when store new one" do
      @published.store(@message1, @context1)
      @published.store(@message2, @context2)
      @published.instance_variable_get(:@cache).keys.should == [@key1, @key2]
      @published.instance_variable_get(:@lru).should == [@key1, @key2]
      flexmock(Time).should_receive(:now).and_return(Time.at(1000031))
      @published.store(@message3, @context3)
      @published.instance_variable_get(:@cache).keys.should == [@key3]
      @published.instance_variable_get(:@lru).should == [@key3]
    end

    it "should fetch message info and make it the most recently used" do
      @published.store(@message1, @context1)
      @published.store(@message2, @context2)
      @published.instance_variable_get(:@lru).should == [@key1, @key2]
      @published.fetch(@message1).should == @context1
      @published.instance_variable_get(:@lru).should == [@key2, @key1]
    end

    it "should fetch empty hash if entry not found" do
      @published.fetch(@message1).should be_nil
      @published.store(@message1, @context1)
      @published.fetch(@message1).should_not be_nil
      @published.fetch(@message2).should be_nil
    end

  end # Published

  describe "Initializing" do

    before(:each) do
      @serializer = flexmock("Serializer")
      @exceptions = RightScale::StatsHelper::ExceptionStats
      @identity = "rs-broker-localhost-5672"
      @address = {:host => "localhost", :port => 5672, :index => 0}
      @broker = flexmock("broker_client", :identity => @identity, :usable? => true)
      @broker.should_receive(:return_message).by_default
      @broker.should_receive(:update_status).by_default
      flexmock(RightScale::BrokerClient).should_receive(:new).and_return(@broker).by_default
      @island1 = flexmock("island1", :id => 11, :broker_hosts => "second:1,first:0", :broker_ports => "5673")
      @island2 = flexmock("island2", :id => 22, :broker_hosts => "third:0,fourth:1", :broker_ports => nil)
      @islands = {11 => @island1, 22 => @island2}
    end

    it "should create a broker client for default host and port" do
      flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity, @address, @serializer,
              @exceptions, Hash, nil, nil).and_return(@broker).once
      ha = RightScale::HABrokerClient.new(@serializer)
      ha.brokers.should == [@broker]
    end

    it "should create broker clients for specified hosts and ports and assign index in order of creation" do
      address1 = {:host => "first", :port => 5672, :index => 0}
      broker1 = flexmock("broker_client1", :identity => "rs-broker-first-5672", :usable? => true, :return_message => true)
      flexmock(RightScale::BrokerClient).should_receive(:new).with("rs-broker-first-5672", address1, @serializer,
              RightScale::StatsHelper::ExceptionStats, Hash, nil, nil).and_return(broker1).once
      address2 = {:host => "second", :port => 5672, :index => 1}
      broker2 = flexmock("broker_client2", :identity => "rs-broker-second-5672", :usable? => true, :return_message => true)
      flexmock(RightScale::BrokerClient).should_receive(:new).with("rs-broker-second-5672", address2, @serializer,
              RightScale::StatsHelper::ExceptionStats, Hash, nil, nil).and_return(broker2).once
      ha = RightScale::HABrokerClient.new(@serializer, :host => "first, second", :port => 5672)
      ha.brokers.should == [broker1, broker2]
      ha.home_island.should be_nil
    end

    it "should create broker clients for specified islands" do
      address1 = {:host => "first", :port => 5673, :index => 0}
      broker1 = flexmock("broker_client1", :identity => "rs-broker-first-5673", :usable? => true, :return_message => true)
      flexmock(RightScale::BrokerClient).should_receive(:new).with("rs-broker-first-5673", address1, @serializer,
              RightScale::StatsHelper::ExceptionStats, Hash, @island1, nil).and_return(broker1).once
      address2 = {:host => "second", :port => 5673, :index => 1}
      broker2 = flexmock("broker_client2", :identity => "rs-broker-second-5673", :usable? => true, :return_message => true)
      flexmock(RightScale::BrokerClient).should_receive(:new).with("rs-broker-second-5673", address2, @serializer,
              RightScale::StatsHelper::ExceptionStats, Hash, @island1, nil).and_return(broker2).once
      address3 = {:host => "third", :port => 5672, :index => 0}
      broker3 = flexmock("broker_client3", :identity => "rs-broker-third-5672", :usable? => true, :return_message => true)
      flexmock(RightScale::BrokerClient).should_receive(:new).with("rs-broker-third-5672", address3, @serializer,
              RightScale::StatsHelper::ExceptionStats, Hash, @island2, nil).and_return(broker3).once
      address4 = {:host => "fourth", :port => 5672, :index => 1}
      broker4 = flexmock("broker_client4", :identity => "rs-broker-fourth-5672", :usable? => true, :return_message => true)
      flexmock(RightScale::BrokerClient).should_receive(:new).with("rs-broker-fourth-5672", address4, @serializer,
              RightScale::StatsHelper::ExceptionStats, Hash, @island2, nil).and_return(broker4).once
      ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => 22)
      ha.brokers.should == [broker3, broker4, broker2, broker1]
      ha.home_island.should == 22
    end

    it "should raise an ArgumentError if it cannot find the home island" do
      flexmock(RightScale::BrokerClient).should_receive(:new).never
      lambda { RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => 33) }.
              should raise_error(ArgumentError, /Could not find home island 33/)
    end

    it "should setup to receive returned messages from each usable broker client" do
      @broker.should_receive(:return_message).twice
      flexmock(RightScale::BrokerClient).should_receive(:new).and_return(@broker).twice
      RightScale::HABrokerClient.new(@serializer, :host => "first, second", :port => 5672)
    end

  end # Initializing

  describe "Parsing user_data" do

    it "should extra host list from RS_rn_url and RS_rn_host" do
      RightScale::HABrokerClient.parse_user_data("RS_rn_url=rs@first/right_net&RS_rn_host=:0,second:1").should ==
        ["first:0,second:1", nil]
    end

    it "should extra port list from RS_rn_port" do
      RightScale::HABrokerClient.parse_user_data("RS_rn_url=rs@host/right_net&RS_rn_host=:1,host:0&RS_rn_port=5673:1,5672:0").should ==
        ["host:1,host:0", "5673:1,5672:0"]
    end

    it "should raise an exception if there is no user data" do
      lambda { RightScale::HABrokerClient.parse_user_data(nil) }.should raise_error(RightScale::HABrokerClient::NoUserData)
      lambda { RightScale::HABrokerClient.parse_user_data("") }.should raise_error(RightScale::HABrokerClient::NoUserData)
    end

    it "should raise an exception if there are no broker hosts defined in the data" do
      lambda { RightScale::HABrokerClient.parse_user_data("blah") }.should raise_error(RightScale::HABrokerClient::NoBrokerHosts)
    end

    it "should translate old host name to standard form" do
      RightScale::HABrokerClient.parse_user_data("RS_rn_url=rs@broker.rightscale.com/right_net").should ==
        ["broker1-1.rightscale.com", nil]
    end

  end # Parsing user_data

  describe "Addressing" do

    it "should form list of broker addresses from specified hosts and ports" do
      RightScale::HABrokerClient.addresses("first,second", "5672, 5674").should ==
        [{:host => "first", :port => 5672, :index => 0}, {:host => "second", :port => 5674, :index => 1}]
    end

    it "should form list of broker addresses from specified hosts and ports and use ids associated with hosts" do
      RightScale::HABrokerClient.addresses("first:1,second:2", "5672, 5674").should ==
        [{:host => "first", :port => 5672, :index => 1}, {:host => "second", :port => 5674, :index => 2}]
    end

    it "should form list of broker addresses from specified hosts and ports and use ids associated with ports" do
      RightScale::HABrokerClient.addresses("host", "5672:0, 5674:2").should ==
        [{:host => "host", :port => 5672, :index => 0}, {:host => "host", :port => 5674, :index => 2}]
    end

    it "should use default host and port for broker identity if none provided" do
      RightScale::HABrokerClient.addresses(nil, nil).should == [{:host => "localhost", :port => 5672, :index => 0}]
    end

    it "should use default port when ports is an empty string" do
      RightScale::HABrokerClient.addresses("first, second", "").should ==
        [{:host => "first", :port => 5672, :index => 0}, {:host => "second", :port => 5672, :index => 1}]
    end

    it "should use default host when hosts is an empty string" do
      RightScale::HABrokerClient.addresses("", "5672, 5673").should ==
        [{:host => "localhost", :port => 5672, :index => 0}, {:host => "localhost", :port => 5673, :index => 1}]
    end

    it "should reuse host if there is only one but multiple ports" do
      RightScale::HABrokerClient.addresses("first", "5672, 5674").should ==
        [{:host => "first", :port => 5672, :index => 0}, {:host => "first", :port => 5674, :index => 1}]
    end

    it "should reuse port if there is only one but multiple hosts" do
      RightScale::HABrokerClient.addresses("first, second", 5672).should ==
        [{:host => "first", :port => 5672, :index => 0}, {:host => "second", :port => 5672, :index => 1}]
    end

    it "should apply ids associated with host" do
      RightScale::HABrokerClient.addresses("first:0, third:2", 5672).should ==
        [{:host => "first", :port => 5672, :index => 0}, {:host => "third", :port => 5672, :index => 2}]
    end

    it "should not allow mismatched number of hosts and ports" do
      runner = lambda { RightScale::HABrokerClient.addresses("first, second", "5672, 5673, 5674") }
      runner.should raise_exception(ArgumentError)
    end

  end # Addressing

  describe "Identifying" do

    before(:each) do
      @serializer = flexmock("Serializer")
      @exceptions = RightScale::StatsHelper::ExceptionStats

      @address1 = {:host => "first", :port => 5672, :index => 0}
      @identity1 = "rs-broker-first-5672"
      @broker1 = flexmock("broker_client1", :identity => @identity1, :usable? => true, :return_message => true,
                          :alias => "b0", :host => "first", :port => 5672, :index => 0)
      @broker1.should_receive(:island_id).and_return(nil).by_default
      @broker1.should_receive(:in_home_island).and_return(true).by_default
      flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity1, @address1, @serializer,
              @exceptions, Hash, nil, nil).and_return(@broker1).by_default

      @address2 = {:host => "second", :port => 5672, :index => 1}
      @identity2 = "rs-broker-second-5672"
      @broker2 = flexmock("broker_client2", :identity => @identity2, :usable? => true, :return_message => true,
                          :alias => "b1", :host => "second", :port => 5672, :index => 1)
      @broker2.should_receive(:island_id).and_return(nil).by_default
      @broker2.should_receive(:in_home_island).and_return(true).by_default
      flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity2, @address2, @serializer,
              @exceptions, Hash, nil, nil).and_return(@broker2).by_default

      @address3 = {:host => "third", :port => 5672, :index => 2}
      @identity3 = "rs-broker-third-5672"
      @broker3 = flexmock("broker_client3", :identity => @identity3, :usable? => true, :return_message => true,
                          :alias => "b2", :host => "third", :port => 5672, :index => 2)
      @broker3.should_receive(:island_id).and_return(nil).by_default
      @broker3.should_receive(:in_home_island).and_return(true).by_default
      flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity3, @address3, @serializer,
              @exceptions, Hash, nil, nil).and_return(@broker3).by_default
    end

    it "should use host and port to uniquely identity broker in AgentIdentity format" do
      RightScale::HABrokerClient.identity("localhost", 5672).should == "rs-broker-localhost-5672"
      RightScale::HABrokerClient.identity("10.21.102.23", 1234).should == "rs-broker-10.21.102.23-1234"
    end

    it "should replace '-' with '~' in host names when forming broker identity" do
      RightScale::HABrokerClient.identity("9-1-1", 5672).should == "rs-broker-9~1~1-5672"
    end

    it "should use default port when forming broker identity" do
      RightScale::HABrokerClient.identity("10.21.102.23").should == "rs-broker-10.21.102.23-5672"
    end

    it "should list broker identities" do
      RightScale::HABrokerClient.identities("first,second", "5672, 5674").should ==
        ["rs-broker-first-5672", "rs-broker-second-5674"]
    end

    it "should convert identities into aliases" do
      ha = RightScale::HABrokerClient.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha.aliases([@identity3]).should == ["b2"]
      ha.aliases([@identity3, @identity1]).should == ["b2", "b0"]
    end

    it "should convert identities into nil alias when unknown" do
      ha = RightScale::HABrokerClient.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha.aliases(["rs-broker-second-5672", nil]).should == [nil, nil]
    end

    it "should convert identity into alias" do
      ha = RightScale::HABrokerClient.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha.alias_(@identity3).should == "b2"
    end

    it "should convert identity into nil alias when unknown" do
      ha = RightScale::HABrokerClient.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha.alias_("rs-broker-second-5672").should == nil
    end

    it "should convert identity into parts" do
      ha = RightScale::HABrokerClient.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha.identity_parts(@identity3).should == ["third", 5672, 2, 1, nil]
    end

    it "should convert an alias into parts" do
      ha = RightScale::HABrokerClient.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha.identity_parts("b2").should == ["third", 5672, 2, 1, nil]
    end

    it "should convert unknown identity into nil parts" do
      ha = RightScale::HABrokerClient.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha.identity_parts("rs-broker-second-5672").should == [nil, nil, nil, nil, nil]
    end

    it "should get identity from identity" do
      ha = RightScale::HABrokerClient.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha.get(@identity1).should == @identity1
      ha.get("rs-broker-second-5672").should be_nil
      ha.get(@identity3).should == @identity3
    end

    it "should get identity from an alias" do
      ha = RightScale::HABrokerClient.new(@serializer, :host => "first:0, third:2", :port => 5672)
      ha.get("b0").should == @identity1
      ha.get("b1").should be_nil
      ha.get("b2").should == @identity3
    end

    it "should generate host:index list" do
      ha = RightScale::HABrokerClient.new(@serializer, :host => "second:1, first:0, third:2", :port => 5672)
      ha.hosts.should == "second:1,first:0,third:2"
    end

    it "should generate port:index list" do
      ha = RightScale::HABrokerClient.new(@serializer, :host => "second:1, third:2, first:0", :port => 5672)
      ha.ports.should == "5672:1,5672:2,5672:0"
    end

    describe "when using islands" do

      before(:each) do
        @island1 = flexmock("island1", :id => 11, :broker_hosts => "second:1,first:0", :broker_ports => "5672")
        @island2 = flexmock("island2", :id => 22, :broker_hosts => "third:0,fourth:1", :broker_ports => nil)
        @islands = {11 => @island1, 22 => @island2}

        @broker1.should_receive(:island_id).and_return(11)
        @broker1.should_receive(:in_home_island).and_return(false)
        flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity1, @address1, @serializer,
                @exceptions, Hash, @island1, nil).and_return(@broker1)

        @broker2.should_receive(:island_id).and_return(11)
        @broker2.should_receive(:in_home_island).and_return(false)
        flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity2, @address2, @serializer,
                @exceptions, Hash, @island1, nil).and_return(@broker2)

        @address3 = {:host => "third", :port => 5672, :index => 0}
        @identity3 = "rs-broker-third-5672"
        @broker3 = flexmock("broker_client3", :identity => @identity3, :usable? => true, :return_message => true,
                            :alias => "b0", :host => "third", :port => 5672, :index => 0)
        @broker3.should_receive(:island_id).and_return(22).by_default
        @broker3.should_receive(:in_home_island).and_return(true)
        flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity3, @address3, @serializer,
                @exceptions, Hash, @island2, nil).and_return(@broker3)

        @address4 = {:host => "fourth", :port => 5672, :index => 1}
        @identity4 = "rs-broker-fourth-5672"
        @broker4 = flexmock("broker_client4", :identity => @identity4, :usable? => true, :return_message => true,
                            :alias => "b1", :host => "fourth", :port => 5672, :index => 1)
        @broker4.should_receive(:island_id).and_return(22)
        @broker4.should_receive(:in_home_island).and_return(true)
        flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity4, @address4, @serializer,
                @exceptions, Hash, @island2, nil).and_return(@broker4)
      end

      it "should convert identity into parts that includes island_id" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => 22)
        ha.identity_parts(@identity1).should == ["first", 5672, 0, 1, 11]
        ha.identity_parts(@identity2).should == ["second", 5672, 1, 0, 11]
        ha.identity_parts(@identity3).should == ["third", 5672, 0, 0, 22]
        ha.identity_parts(@identity4).should == ["fourth", 5672, 1, 1, 22]
      end

      it "should generate host:index list for home island" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => 22)
        ha.hosts.should == "third:0,fourth:1"
        ha.hosts(22).should == "third:0,fourth:1"
      end

      it "should generate host:index list for other island" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => 22)
        ha.hosts(11).should == "second:1,first:0"
      end

      it "should generate port:index list for home island" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => 22)
        ha.ports.should == "5672:0,5672:1"
        ha.ports(22).should == "5672:0,5672:1"
      end

      it "should generate port:index list for other island" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => 22)
        ha.ports(11).should == "5672:1,5672:0"
      end

    end

  end # Identifying

  describe "When" do

    before(:each) do
      @serializer = flexmock("Serializer")
      @exceptions = RightScale::StatsHelper::ExceptionStats

      @island1 = flexmock("island1", :id => 11, :index => 0, :broker_ports => nil)
      @island1.should_receive(:broker_hosts).and_return("first:0,second:1").by_default
      @island2 = flexmock("island2", :id => 22, :index => 1, :broker_ports => nil)
      @island2.should_receive(:broker_hosts).and_return("third:0,fourth:1").by_default
      @islands = {11 => @island1, 22 => @island2}
      @home = 22

      # Generate mocking for five BrokerClients in two islands with second being home island
      # The fifth client is not configured for use except when doing island updates
      # key index host     alias island_id
      { 1 => [0, "first",  "i0b0", 1],
        2 => [1, "second", "i0b1", 1],
        3 => [0, "third",  "b0"  , 2],
        4 => [1, "fourth", "b1"  , 2],
        5 => [2, "fifth",  "b2"  , 2] }.each do |k, v|
              i, h,         a,     d = v
        eval("@identity#{k} = 'rs-broker-#{h}-5672'")
        eval("@address#{k} = {:host => '#{h}', :port => 5672, :index => #{i}}")
        eval("@broker#{k} = flexmock('broker_client#{k}', :identity => @identity#{k}, :alias => '#{a}', " +
                                      ":host => '#{h}', :port => 5672, :index => #{i}, :island_id => #{d}#{d}, " +
                                      ":in_home_island => #{d}#{d} == @home)")
        eval("@broker#{k}.should_receive(:status).and_return(:connected).by_default")
        eval("@broker#{k}.should_receive(:usable?).and_return(true).by_default")
        eval("@broker#{k}.should_receive(:connected?).and_return(true).by_default")
        eval("@broker#{k}.should_receive(:subscribe).and_return(true).by_default")
        eval("@broker#{k}.should_receive(:return_message).and_return(true).by_default")
        eval("flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity#{k}, @address#{k}, " +
                       "@serializer, @exceptions, Hash, @island#{d}, nil).and_return(@broker#{k}).by_default")
      end
    end
  
    describe "Connecting" do

      # Generate mocking for three BrokerClients that do not use islands
      before(:each) do
        {0 => "a", 1 => "b", 2 => "c"}.each do |i, h|
          eval("@identity_#{h} = 'rs-broker-#{h}-5672'")
          eval("@address_#{h} = {:host => '#{h}', :port => 5672, :index => #{i}}")
          eval("@broker_#{h} = flexmock('broker_client_#{h}', :identity => @identity_#{h}, :alias => 'b#{i}', " +
                                        ":host => '#{h}', :port => 5672, :index => #{i}, :island_id => nil, " +
                                        ":in_home_island => true)")
          eval("@broker_#{h}.should_receive(:usable?).and_return(true).by_default")
          eval("@broker_#{h}.should_receive(:return_message).and_return(true).by_default")
          eval("flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity_#{h}, @address_#{h}, " +
                         "@serializer, @exceptions, Hash, nil, any).and_return(@broker_#{h}).by_default")
        end
      end

      it "should connect and add a new broker client to the end of the list" do
        ha = RightScale::HABrokerClient.new(@serializer, :host => "a", :port => 5672)
        ha.brokers.size.should == 1
        ha.brokers[0].alias == "b0"
        flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity_b, @address_b, @serializer,
                 @exceptions, Hash, nil, nil).and_return(@broker_b).once
        res = ha.connect("b", 5672, 1)
        res.should be_true
        ha.brokers.size.should == 2
        ha.brokers[1].alias == "b1"
      end

      it "should reconnect an existing broker client after closing it if it is not connected" do
        ha = RightScale::HABrokerClient.new(@serializer, :host => "a, b")
        ha.brokers.size.should == 2
        @broker_a.should_receive(:usable?).and_return(false)
        @broker_a.should_receive(:close).and_return(true).once
        flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity_a, @address_a, @serializer,
                 @exceptions, Hash, nil, ha.brokers[0]).and_return(@broker_a).once
        res = ha.connect("a", 5672, 0)
        res.should be_true
        ha.brokers.size.should == 2
        ha.brokers[0].alias == "b0"
        ha.brokers[1].alias == "b1"
      end

      it "should a new broker client and reconnect broker clients when an island is specified" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => {22 => @island2}, :home_island => @home)
        ha.brokers.size.should == 2
        ha.brokers[0].alias == "b0"
        ha.brokers[1].alias == "b1"
        flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity2, @address2, @serializer,
                 @exceptions, Hash, @island1, nil).and_return(@broker2).by_default
        res = ha.connect("second", 5672, 1, nil, @island1)
        res.should be_true
        ha.brokers.size.should == 3
        ha.brokers[0].alias == "b0"
        ha.brokers[1].alias == "b1"
        ha.brokers[2].alias == "i0b1"
        @broker3.should_receive(:usable?).and_return(false)
        @broker3.should_receive(:close).and_return(true).once
        flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity3, @address3, @serializer,
                 @exceptions, Hash, @island2, ha.brokers[0]).and_return(@broker3).by_default
        res = ha.connect("third", 5672, 0, nil, @island2)
        res.should be_true
        ha.brokers.size.should == 3
        ha.brokers[0].alias == "b0"
        ha.brokers[1].alias == "b1"
        ha.brokers[2].alias == "i0b1"
        flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity1, @address1, @serializer,
                 @exceptions, Hash, @island1, nil).and_return(@broker1).by_default
        res = ha.connect("first", 5672, 0, 0, @island1)
        res.should be_true
        ha.brokers.size.should == 4
        ha.brokers[0].alias == "b0"
        ha.brokers[1].alias == "b1"
        ha.brokers[2].alias == "i0b0"
        ha.brokers[3].alias == "i0b1"
      end

      it "should not do anything except log a message if asked to reconnect an already connected broker client" do
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Ignored request to reconnect/).once
        ha = RightScale::HABrokerClient.new(@serializer, :host => "a, b")
        ha.brokers.size.should == 2
        @broker_a.should_receive(:status).and_return(:connected).once
        @broker_a.should_receive(:close).and_return(true).never
        flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity_a, @address_a, @serializer,
                 @exceptions, Hash, nil, ha.brokers[0]).and_return(@broker_a).never
        res = ha.connect("a", 5672, 0)
        res.should be_false
        ha.brokers.size.should == 2
        ha.brokers[0].alias == "b0"
        ha.brokers[1].alias == "b1"
      end

      it "should reconnect already connected broker client if force specified" do
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Ignored request to reconnect/).never
        ha = RightScale::HABrokerClient.new(@serializer, :host => "a, b")
        ha.brokers.size.should == 2
        @broker_a.should_receive(:close).and_return(true).once
        flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity_a, @address_a, @serializer,
                 @exceptions, Hash, nil, ha.brokers[0]).and_return(@broker_a).once
        res = ha.connect("a", 5672, 0, nil, nil, force = true)
        res.should be_true
        ha.brokers.size.should == 2
        ha.brokers[0].alias == "b0"
        ha.brokers[1].alias == "b1"
      end

      it "should slot broker client into specified priority position when at end of list" do
        ha = RightScale::HABrokerClient.new(@serializer, :host => "a, b")
        ha.brokers.size.should == 2
        res = ha.connect("c", 5672, 2, 2)
        res.should be_true
        ha.brokers.size.should == 3
        ha.brokers[0].alias == "b0"
        ha.brokers[1].alias == "b1"
        ha.brokers[2].alias == "b2"
      end

      it "should slot broker client into specified priority position when already is a client in that position" do
        ha = RightScale::HABrokerClient.new(@serializer, :host => "a, b")
        ha.brokers.size.should == 2
        res = ha.connect("c", 5672, 2, 1)
        res.should be_true
        ha.brokers.size.should == 3
        ha.brokers[0].alias == "b0"
        ha.brokers[1].alias == "b2"
        ha.brokers[2].alias == "b1"
      end

      it "should slot broker client into nex priority position if specified priority would leave a gap" do
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Reduced priority setting for broker/).once
        ha = RightScale::HABrokerClient.new(@serializer, :host => "a")
        ha.brokers.size.should == 1
        res = ha.connect("c", 5672, 2, 2)
        res.should be_true
        ha.brokers.size.should == 2
        ha.brokers[0].alias == "b0"
        ha.brokers[1].alias == "b2"
      end

      it "should yield to the block provided with the newly connected broker identity" do
        ha = RightScale::HABrokerClient.new(@serializer, :host => "a")
        ha.brokers.size.should == 1
        ha.brokers[0].alias == "b0"
        identity = nil
        res = ha.connect("b", 5672, 1) { |i| identity = i }
        res.should be_true
        identity.should == @identity_b
        ha.brokers.size.should == 2
        ha.brokers[1].alias == "b1"
      end

      it "should raise an exception if try to change host and port of an existing broker client" do
        ha = RightScale::HABrokerClient.new(@serializer, :host => "a, b")
        lambda { ha.connect("c", 5672, 0) }.should raise_error(Exception, /Not allowed to change host or port/)
      end

    end # Connecting

    describe "Connection updating" do

      it "should connect to any brokers for which not currently connected and return their identity" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.brokers.size.should == 4
        @island2.should_receive(:broker_hosts).and_return("third:0,fourth:1,fifth:2")
        ha.connect_update(@islands)
        ha.brokers.size.should == 5
        ha.brokers[0].alias.should == "b0"
        ha.brokers[1].alias.should == "b1"
        ha.brokers[2].alias.should == "b2"
        ha.brokers[3].alias.should == "i0b0"
        ha.brokers[4].alias.should == "i0b1"
        ha.instance_variable_get(:@brokers_hash)[@identity5].should == @broker5
      end

      it "should do nothing if there is no change" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.brokers.size.should == 4
        ha.connect_update(@islands)
        ha.brokers.size.should == 4
        ha.brokers[0].alias.should == "b0"
        ha.brokers[1].alias.should == "b1"
        ha.brokers[2].alias.should == "i0b0"
        ha.brokers[3].alias.should == "i0b1"
      end

      it "should remove any broker clients for islands in which they are no longer configured" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.brokers.size.should == 4
        @broker1.should_receive(:close).and_return(true).once
        @broker3.should_receive(:close).and_return(true).once
        @island1.should_receive(:broker_hosts).and_return("second:1")
        @island2.should_receive(:broker_hosts).and_return("fourth:1,fifth:2")
        ha.connect_update(@islands)
        ha.brokers.size.should == 3
        ha.brokers[0].alias.should == "b2"
        ha.brokers[1].alias.should == "b1"
        ha.brokers[2].alias.should == "i0b1"
        ha.instance_variable_get(:@brokers_hash)[@identity1].should be_nil
        ha.instance_variable_get(:@brokers_hash)[@identity3].should be_nil
        ha.instance_variable_get(:@brokers_hash)[@identity5].should == @broker5
      end

    end # Connection updating

    describe "Subscribing" do

      it "should subscribe on all usable broker clients and return their identities" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:usable?).and_return(false)
        @broker1.should_receive(:subscribe).never
        @broker2.should_receive(:subscribe).and_return(true).once
        @broker3.should_receive(:subscribe).and_return(true).once
        @broker4.should_receive(:subscribe).and_return(true).once
        result = ha.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"})
        result.should == [@identity3, @identity4, @identity2]
      end

      it "should not return the identity if subscribe fails" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:usable?).and_return(false)
        @broker1.should_receive(:subscribe).never
        @broker2.should_receive(:subscribe).and_return(true).once
        @broker3.should_receive(:subscribe).and_return(false).once
        @broker4.should_receive(:subscribe).and_return(true).once
        result = ha.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"})
        result.should == [@identity4, @identity2]
      end

      it "should subscribe only on specified brokers" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:usable?).and_return(false)
        @broker1.should_receive(:subscribe).never
        @broker2.should_receive(:subscribe).and_return(true).once
        @broker3.should_receive(:subscribe).never
        @broker4.should_receive(:subscribe).never
        result = ha.subscribe({:name => "queue"}, {:type => :direct, :name => "exchange"},
                              :brokers => [@identity1, @identity2])
        result.should == [@identity2]
      end

    end # Subscribing

    describe "Unsubscribing" do

      before(:each) do
        @timer = flexmock("timer", :cancel => true).by_default
        flexmock(EM::Timer).should_receive(:new).and_return(@timer).by_default
        @queue_name = "my_queue"
        @queue = flexmock("queue", :name => @queue_name)
        @queues = [@queue]
        @broker1.should_receive(:queues).and_return(@queues).by_default
        @broker1.should_receive(:unsubscribe).and_return(true).and_yield.by_default
        @broker2.should_receive(:queues).and_return(@queues).by_default
        @broker2.should_receive(:unsubscribe).and_return(true).and_yield.by_default
        @broker3.should_receive(:queues).and_return(@queues).by_default
        @broker3.should_receive(:unsubscribe).and_return(true).and_yield.by_default
        @broker4.should_receive(:queues).and_return(@queues).by_default
        @broker4.should_receive(:unsubscribe).and_return(true).and_yield.by_default
      end

      it "should unsubscribe from named queues on all usable broker clients" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:usable?).and_return(false)
        @broker1.should_receive(:unsubscribe).never
        @broker2.should_receive(:unsubscribe).and_return(true).once
        @broker3.should_receive(:unsubscribe).and_return(true).once
        @broker4.should_receive(:unsubscribe).and_return(true).once
        ha.unsubscribe([@queue_name]).should be_true
      end

      it "should yield to supplied block after unsubscribing" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.subscribe({:name => @queue_name}, {:type => :direct, :name => "exchange"})
        called = 0
        ha.unsubscribe([@queue_name]) { called += 1 }
        called.should == 1
      end

      it "should yield to supplied block if timeout before finish unsubscribing" do
        flexmock(EM::Timer).should_receive(:new).with(10, Proc).and_return(@timer).and_yield.once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.subscribe({:name => @queue_name}, {:type => :direct, :name => "exchange"})
        called = 0
        ha.unsubscribe([@queue_name], 10) { called += 1 }
        called.should == 1
      end

      it "should cancel timer if finish unsubscribing before timer fires" do
        @timer.should_receive(:cancel).once
        flexmock(EM::Timer).should_receive(:new).with(10, Proc).and_return(@timer).once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.subscribe({:name => @queue_name}, {:type => :direct, :name => "exchange"})
        called = 0
        ha.unsubscribe([@queue_name], 10) { called += 1 }
        called.should == 1
      end

      it "should yield to supplied block after unsubscribing even if no queues to unsubscribe" do
        @broker1.should_receive(:queues).and_return([])
        @broker2.should_receive(:queues).and_return([])
        @broker3.should_receive(:queues).and_return([])
        @broker4.should_receive(:queues).and_return([])
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        called = 0
        ha.unsubscribe([@queue_name]) { called += 1 }
        called.should == 1
      end

      it "should yield to supplied block once after unsubscribing all queues" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.subscribe({:name => @queue_name}, {:type => :direct, :name => "exchange"})
        called = 0
        ha.unsubscribe([@queue_name]) { called += 1 }
        called.should == 1
      end

    end # Unsubscribing

    describe "Declaring" do

      it "should declare exchange on all usable broker clients and return their identities" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:usable?).and_return(false)
        @broker1.should_receive(:declare).never
        @broker2.should_receive(:declare).and_return(true).once
        @broker3.should_receive(:declare).and_return(true).once
        @broker4.should_receive(:declare).and_return(true).once
        result = ha.declare(:exchange, "x", :durable => true)
        result.should == [@identity3, @identity4, @identity2]
      end

      it "should not return the identity if declare fails" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:usable?).and_return(false)
        @broker1.should_receive(:declare).never
        @broker2.should_receive(:declare).and_return(true).once
        @broker3.should_receive(:declare).and_return(false).once
        @broker4.should_receive(:declare).and_return(true).once
        result = ha.declare(:exchange, "x", :durable => true)
        result.should == [@identity4, @identity2]
      end

      it "should declare exchange only on specified brokers" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:usable?).and_return(false)
        @broker1.should_receive(:declare).never
        @broker2.should_receive(:declare).and_return(true).once
        @broker3.should_receive(:declare).never
        @broker4.should_receive(:declare).never
        result = ha.declare(:exchange, "x", :durable => true, :brokers => [@identity1, @identity2])
        result.should == [@identity2]
      end

    end # Declaring

    describe "Publishing" do

      before(:each) do
        @message = flexmock("message")
        @packet = flexmock("packet", :class => RightScale::Request, :to_s => true, :version => [12, 12]).by_default
        @serializer.should_receive(:dump).with(@packet).and_return(@message).by_default
        @broker1.should_receive(:publish).and_return(true).by_default
        @broker2.should_receive(:publish).and_return(true).by_default
        @broker3.should_receive(:publish).and_return(true).by_default
        @broker4.should_receive(:publish).and_return(true).by_default
      end

      it "should serialize message, publish it, and return list of broker identifiers" do
        @serializer.should_receive(:dump).with(@packet).and_return(@message).once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.publish({:type => :direct, :name => "exchange", :options => {:durable => true}},
                   @packet, :persistent => true).should == [@identity3]
      end

      it "should try other broker clients if a publish fails" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker3.should_receive(:publish).and_return(false)
        ha.publish({:type => :direct, :name => "exchange"}, @packet).should == [@identity4]
      end

      it "should only try to use home island brokers by default" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker3.should_receive(:publish).and_return(false)
        @broker4.should_receive(:publish).and_return(false)
        lambda { ha.publish({:type => :direct, :name => "exchange"}, @packet) }.
                should raise_error(RightScale::HABrokerClient::NoConnectedBrokers)
      end

      it "should publish to a randomly selected broker if random requested" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        srand(100)
        ha.publish({:type => :direct, :name => "exchange"}, @packet, :order => :random,
                   :brokers =>[@identity1, @identity2, @identity3, @identity4]).should == [@identity2]
      end

      it "should publish to all connected brokers if fanout requested" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.publish({:type => :direct, :name => "exchange"}, @packet, :fanout => true,
                   :brokers =>[@identity1, @identity2]).should == [@identity1, @identity2]
      end

      it "should publish only using specified brokers" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.publish({:type => :direct, :name => "exchange"}, @packet,
                   :brokers =>[@identity1, @identity2]).should == [@identity1]
      end

      it "should log an error if a selected broker is unknown but still publish with any remaining brokers" do
        flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Invalid broker identity "rs-broker-fifth-5672"/).once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.publish({:type => :direct, :name => "exchange"}, @packet,
                   :brokers =>["rs-broker-fifth-5672", @identity1]).should == [@identity1]
      end

      it "should raise an exception if all available brokers fail to publish" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker3.should_receive(:publish).and_return(false)
        @broker4.should_receive(:publish).and_return(false)
        lambda { ha.publish({:type => :direct, :name => "exchange"}, @packet) }.
                should raise_error(RightScale::HABrokerClient::NoConnectedBrokers)
      end

      it "should not serialize the message if it is already serialized" do
        @serializer.should_receive(:dump).with(@packet).and_return(@message).never
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.publish({:type => :direct, :name => "exchange"}, @packet, :no_serialize => true).should == [@identity3]
      end

      it "should store message info for use by message returns if :mandatory specified" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.publish({:type => :direct, :name => "exchange"}, @packet, :mandatory => true).should == [@identity3]
        ha.instance_variable_get(:@published).instance_variable_get(:@cache).size.should == 1
      end

      it "should not store message info for use by message returns if message already serialized" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.publish({:type => :direct, :name => "exchange"}, @packet, :no_serialize => true).should == [@identity3]
        ha.instance_variable_get(:@published).instance_variable_get(:@cache).size.should == 0
      end

      it "should not store message info for use by message returns if mandatory not specified" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.publish({:type => :direct, :name => "exchange"}, @packet).should == [@identity3]
        ha.instance_variable_get(:@published).instance_variable_get(:@cache).size.should == 0
      end

    end # Publishing

    describe "Returning" do

      before(:each) do
        @message = flexmock("message")
        @packet = flexmock("packet", :class => RightScale::Request, :to_s => true, :version => [12, 12]).by_default
        @serializer.should_receive(:dump).with(@packet).and_return(@message).by_default
        @broker1.should_receive(:publish).and_return(true).by_default
        @broker2.should_receive(:publish).and_return(true).by_default
        @broker3.should_receive(:publish).and_return(true).by_default
        @broker4.should_receive(:publish).and_return(true).by_default
      end

      it "should invoke return block" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:return_message).and_yield("exchange", "NO_CONSUMERS", @message).once
        called = 0
        ha.return_message do |id, reason, message, to, context|
          called += 1
          id.should == @identity1
          reason.should == "NO_CONSUMERS"
          message.should == @message
          to.should == "exchange"
        end
        called.should == 1
      end

      it "should record failure in message context if there is message context" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.publish({:type => :direct, :name => "exchange", :options => {:durable => true}},
                   @packet, :mandatory => true).should == [@identity3]
        @broker3.should_receive(:return_message).and_yield("exchange", "NO_CONSUMERS", @message).once
        ha.return_message do |id, reason, message, to, context|
          id.should == @identity3
          reason.should == "NO_CONSUMERS"
          message.should == @message
          to.should == "exchange"
        end
        ha.instance_variable_get(:@published).fetch(@message).failed.should == [@identity3]
      end

      describe "when non-delivery" do

        it "should store non-delivery block for use by return handler" do
          ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
          non_delivery = lambda {}
          ha.non_delivery(&non_delivery)
          ha.instance_variable_get(:@non_delivery).should == non_delivery
        end

      end

      describe "when handling return" do

        before(:each) do
          @options = {}
          @brokers = [@identity3, @identity4]
          @context = RightScale::HABrokerClient::Context.new(@packet, @options, @brokers)
        end

        it "should republish using a broker not yet tried if possible and log that re-routing" do
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/RE-ROUTE/).once
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/RETURN reason/).once
          ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
          @context.record_failure(@identity3)
          @broker4.should_receive(:publish).and_return(true).once
          ha.__send__(:handle_return, @identity3, "reason", @message, "to", @context)
        end

        it "should republish to same broker without mandatory if message is persistent and no other brokers available" do
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/RE-ROUTE/).once
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/RETURN reason/).once
          ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
          @context.record_failure(@identity3)
          @context.record_failure(@identity4)
          @packet.should_receive(:persistent).and_return(true)
          @broker3.should_receive(:publish).and_return(true).once
          ha.__send__(:handle_return, @identity4, "NO_CONSUMERS", @message, "to", @context)
        end

        it "should republish to same broker without mandatory if message is one-way and no other brokers available" do
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/RE-ROUTE/).once
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/RETURN reason/).once
          ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
          @context.record_failure(@identity3)
          @context.record_failure(@identity4)
          @packet.should_receive(:one_way).and_return(true)
          @broker3.should_receive(:publish).and_return(true).once
          ha.__send__(:handle_return, @identity4, "NO_CONSUMERS", @message, "to", @context)
        end

        it "should update status to :stopping if message returned because access refused" do
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/RE-ROUTE/).once
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/RETURN reason/).once
          ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
          @context.record_failure(@identity3)
          @broker4.should_receive(:publish).and_return(true).once
          @broker3.should_receive(:update_status).with(:stopping).and_return(true).once
          ha.__send__(:handle_return, @identity3, "ACCESS_REFUSED", @message, "to", @context)
        end

        it "should log info and make non-delivery call even if persistent when returned because of no queue" do
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/NO ROUTE/).once
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/RETURN reason/).once
          ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
          called = 0
          ha.non_delivery { |reason, type, token, from, to| called += 1 }
          @context.record_failure(@identity3)
          @context.record_failure(@identity4)
          @packet.should_receive(:persistent).and_return(true)
          @broker3.should_receive(:publish).and_return(true).never
          @broker4.should_receive(:publish).and_return(true).never
          ha.__send__(:handle_return, @identity4, "NO_QUEUE", @message, "to", @context)
          called.should == 1
        end

        it "should log info and make non-delivery call if no route can be found" do
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/NO ROUTE/).once
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/RETURN reason/).once
          ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
          called = 0
          ha.non_delivery { |reason, type, token, from, to| called += 1 }
          @context.record_failure(@identity3)
          @context.record_failure(@identity4)
          @broker3.should_receive(:publish).and_return(true).never
          @broker4.should_receive(:publish).and_return(true).never
          ha.__send__(:handle_return, @identity4, "any reason", @message, "to", @context)
          called.should == 1
        end

      end

    end # Returning

    describe "Deleting" do

      it "should delete queue on all usable broker clients and return their identities" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:usable?).and_return(false)
        @broker1.should_receive(:delete).never
        @broker2.should_receive(:delete).and_return(true).once
        @broker3.should_receive(:delete).and_return(true).once
        @broker4.should_receive(:delete).and_return(true).once
        ha.delete("queue").should == [@identity3, @identity4, @identity2]
      end

      it "should not return the identity if delete fails" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:usable?).and_return(false)
        @broker1.should_receive(:delete).never
        @broker2.should_receive(:delete).and_return(true).once
        @broker3.should_receive(:delete).and_return(false).once
        @broker4.should_receive(:delete).and_return(true).once
        ha.delete("queue").should == [@identity4, @identity2]
      end

    end # Deleting

    describe "Removing" do

      it "should remove broker client after disconnecting and pass identity to block" do
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Removing/).once
        @broker2.should_receive(:close).with(true, true, false).once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        identity = nil
        result = ha.remove("second", 5672) { |i| identity = i }
        result.should == @identity2
        identity.should == @identity2
        ha.get(@identity2).should be_nil
        ha.get(@identity1).should_not be_nil
        ha.get(@identity3).should_not be_nil
        ha.get("rs-broker-fourth-5672").should_not be_nil
        ha.brokers.size.should == 3
      end

      it "should remove broker when no block supplied but still return a result" do
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Removing/).once
        @broker2.should_receive(:close).once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        result = ha.remove("second", 5672)
        result.should == @identity2
        ha.get(@identity2).should be_nil
        ha.get(@identity1).should_not be_nil
        ha.get(@identity3).should_not be_nil
        ha.get(@identity4).should_not be_nil
        ha.brokers.size.should == 3
      end

      it "should remove last broker if requested" do
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Removing/).times(4)
        @broker1.should_receive(:close).once
        @broker2.should_receive(:close).once
        @broker3.should_receive(:close).once
        @broker4.should_receive(:close).once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        result = ha.remove("second", 5672)
        result.should == @identity2
        ha.get(@identity2).should be_nil
        result = ha.remove("third", 5672)
        result.should == @identity3
        ha.get(@identity3).should be_nil
        result = ha.remove("fourth", 5672)
        result.should == @identity4
        ha.get(@identity4).should be_nil
        ha.brokers.size.should == 1
        identity = nil
        result = ha.remove("first", 5672) { |i| identity = i }
        result.should == @identity1
        identity.should == @identity1
        ha.get(@identity1).should be_nil
        ha.brokers.size.should == 0
      end

      it "should return nil and not execute block if broker is unknown" do
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Ignored request to remove/).once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.remove("fifth", 5672).should be_nil
        ha.brokers.size.should == 4
      end

      it "should close connection and mark as failed when told broker is not usable" do
        @broker2.should_receive(:close).with(true, false, false).once
        @broker3.should_receive(:close).with(true, false, false).once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        result = ha.declare_unusable([@identity2, @identity3])
        ha.brokers.size.should == 4
      end

      it "should raise an exception if broker that is declared not usable is unknown" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        lambda { ha.declare_unusable(["rs-broker-fifth-5672"]) }.should raise_error(Exception, /Cannot mark unknown/)
        ha.brokers.size.should == 4
      end

    end # Removing

    describe "Monitoring" do

      include RightScale::StatsHelper

      before(:each) do
        @timer = flexmock("timer")
        flexmock(EM::Timer).should_receive(:new).and_return(@timer).by_default
        @timer.should_receive(:cancel).by_default
        @identity = "rs-broker-localhost-5672"
        @address = {:host => "localhost", :port => 5672, :index => 0}
        @broker = flexmock("broker_client", :identity => @identity, :alias => "b0", :host => "localhost",
                            :port => 5672, :index => 0, :island_id => nil, :in_home_island => true)
        @broker.should_receive(:status).and_return(:connected).by_default
        @broker.should_receive(:usable?).and_return(true).by_default
        @broker.should_receive(:connected?).and_return(true).by_default
        @broker.should_receive(:subscribe).and_return(true).by_default
        @broker.should_receive(:return_message).and_return(true).by_default
        flexmock(RightScale::BrokerClient).should_receive(:new).and_return(@broker).by_default
      end

      it "should give access to or list usable brokers" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        aliases = []
        res = ha.__send__(:each_usable) { |b| aliases << b.alias }
        aliases.should == ["b0", "b1", "i0b0", "i0b1"]
        res.size.should == 4
        res[0].alias.should == "b0"
        res[1].alias.should == "b1"
        res[2].alias.should == "i0b0"
        res[3].alias.should == "i0b1"

        @broker1.should_receive(:usable?).and_return(true)
        @broker2.should_receive(:usable?).and_return(false)
        @broker3.should_receive(:usable?).and_return(false)
        @broker4.should_receive(:usable?).and_return(false)
        aliases = []
        res = ha.__send__(:each_usable) { |b| aliases << b.alias }
        aliases.should == ["i0b0"]
        res.size.should == 1
        res[0].alias.should == "i0b0"
      end

      it "should give list of unusable brokers" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:usable?).and_return(true)
        @broker2.should_receive(:usable?).and_return(false)
        @broker3.should_receive(:usable?).and_return(false)
        @broker4.should_receive(:usable?).and_return(true)
        ha.unusable.should == [@identity3, @identity2]
      end

      it "should give access to each selected usable broker" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker2.should_receive(:usable?).and_return(true)
        @broker3.should_receive(:usable?).and_return(false)
        aliases = []
        res = ha.__send__(:each_usable, [@identity2, @identity3]) { |b| aliases << b.alias }
        aliases.should == ["i0b1"]
        res.size.should == 1
        res[0].alias.should == "i0b1"
      end

      it "should tell whether a broker is connected" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker2.should_receive(:connected?).and_return(false)
        @broker3.should_receive(:connected?).and_return(true)
        ha.connected?(@identity2).should be_false
        ha.connected?(@identity3).should be_true
        ha.connected?("rs-broker-fifth-5672").should be_nil
      end

      it "should give list of connected brokers for home island by default" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:connected?).and_return(true)
        @broker2.should_receive(:connected?).and_return(false)
        @broker3.should_receive(:connected?).and_return(true)
        @broker4.should_receive(:connected?).and_return(false)
        ha.connected.should == [@identity3]
      end

      it "should give list of connected brokers for a specific island" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:connected?).and_return(true)
        @broker2.should_receive(:connected?).and_return(false)
        @broker3.should_receive(:connected?).and_return(true)
        @broker4.should_receive(:connected?).and_return(false)
        ha.connected(11).should == [@identity1]
        ha.connected(22).should == [@identity3]
      end

      it "should give list of all brokers" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.all.should == [@identity3, @identity4, @identity1, @identity2]
      end

      it "should give list of failed brokers" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:failed?).and_return(true)
        @broker2.should_receive(:failed?).and_return(false)
        @broker3.should_receive(:failed?).and_return(true)
        @broker4.should_receive(:failed?).and_return(false)
        ha.failed.should == [@identity3, @identity1]
      end

      it "should give broker client status list" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:summary).and_return("summary1")
        @broker2.should_receive(:summary).and_return("summary2")
        @broker3.should_receive(:summary).and_return("summary3")
        @broker4.should_receive(:summary).and_return("summary4")
        ha.status.should == ["summary3", "summary4", "summary1", "summary2"]
      end

      it "should give broker client statistics" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:stats).and_return("stats1")
        @broker2.should_receive(:stats).and_return("stats2")
        @broker3.should_receive(:stats).and_return("stats3")
        @broker4.should_receive(:stats).and_return("stats4")
        ha.stats.should == {"brokers" => ["stats3", "stats4", "stats1", "stats2"],
                            "exceptions" => nil,
                            "returns" => nil}
      end

      it "should log broker client status update if there is a change" do
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Broker b0 is now connected/).once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.__send__(:update_status, @broker3, false)
      end

      it "should not log broker client status update if there is no change" do
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Broker b0 is now connected/).never
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.__send__(:update_status, @broker3, true)
      end

      it "should log broker client status update when become disconnected" do
        flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Broker b0 is now disconnected/).once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker3.should_receive(:status).and_return(:disconnected)
        @broker3.should_receive(:connected?).and_return(false)
        ha.__send__(:update_status, @broker3, true)
      end

      it "should provide connection status callback when cross 0/1 connection boundary for home island" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        connected = 0
        disconnected = 0
        ha.connection_status do |status|
          if status == :connected
            (ha.brokers[0].status == :connected ||
             ha.brokers[1].status == :connected).should be_true
            connected += 1
          elsif status == :disconnected
            (ha.brokers[0].status == :disconnected &&
             ha.brokers[1].status == :disconnected).should be_true
            disconnected += 1
          end
        end
        ha.__send__(:update_status, @broker3, false)
        connected.should == 0
        disconnected.should == 0
        @broker3.should_receive(:status).and_return(:disconnected)
        @broker3.should_receive(:connected?).and_return(false)
        ha.__send__(:update_status, @broker3, true)
        connected.should == 0
        disconnected.should == 0
        @broker4.should_receive(:status).and_return(:disconnected)
        @broker4.should_receive(:connected?).and_return(false)
        ha.__send__(:update_status, @broker4, true)
        connected.should == 0
        disconnected.should == 1
        # TODO fix this test so that also checks crossing boundary as become connected
      end

      it "should provide connection status callback when cross n/n-1 connection boundary for home island when all specified" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        connected = 0
        disconnected = 0
        ha.connection_status(:boundary => :all) do |status|
          if status == :connected
            (ha.brokers[0].status == :connected &&
             ha.brokers[1].status == :connected).should be_true
            connected += 1
          elsif status == :disconnected
            (ha.brokers[0].status == :disconnected ||
             ha.brokers[1].status == :disconnected).should be_true
            disconnected += 1
          end
        end
        ha.__send__(:update_status, @broker3, false)
        connected.should == 1
        disconnected.should == 0
        @broker3.should_receive(:status).and_return(:disconnected)
        @broker3.should_receive(:connected?).and_return(false)
        ha.__send__(:update_status, @broker3, true)
        connected.should == 1
        disconnected.should == 1
        @broker4.should_receive(:status).and_return(:disconnected)
        @broker4.should_receive(:connected?).and_return(false)
        ha.__send__(:update_status, @broker4, true)
        connected.should == 1
        disconnected.should == 1
        # TODO fix this test so that also checks crossing boundary as become disconnected
      end

      it "should provide connection status callback when cross connection boundary for non-home island" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:island_alias).and_return(:i0)
        @broker2.should_receive(:island_alias).and_return(:i0)
        connected = 0
        disconnected = 0
        ha.connection_status do |status|
          if status == :connected
            (ha.brokers[2].status == :connected ||
             ha.brokers[3].status == :connected).should be_true
            connected += 1
          elsif status == :disconnected
            (ha.brokers[2].status == :disconnected &&
             ha.brokers[3].status == :disconnected).should be_true
            disconnected += 1
          end
        end
        ha.__send__(:update_status, @broker1, false)
        connected.should == 0
        disconnected.should == 0
        @broker1.should_receive(:status).and_return(:disconnected)
        @broker1.should_receive(:connected?).and_return(false)
        ha.__send__(:update_status, @broker1, true)
        connected.should == 0
        disconnected.should == 0
        @broker2.should_receive(:status).and_return(:disconnected)
        @broker2.should_receive(:connected?).and_return(false)
        ha.__send__(:update_status, @broker2, true)
        connected.should == 0
        disconnected.should == 1
      end

      it "should provide connection status callback for specific broker set" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        @broker1.should_receive(:island_alias).and_return(:i0)
        @broker2.should_receive(:island_alias).and_return(:i0)
        connected = 0
        disconnected = 0
        ha.connection_status(:brokers => [@identity1, @identity2]) do |status|
          if status == :connected
            (ha.brokers[2].status == :connected ||
             ha.brokers[3].status == :connected).should be_true
            connected += 1
          elsif status == :disconnected
            (ha.brokers[2].status == :disconnected &&
             ha.brokers[3].status == :disconnected).should be_true
            disconnected += 1
          end
        end
        ha.__send__(:update_status, @broker1, false)
        connected.should == 0
        disconnected.should == 0
        @broker1.should_receive(:status).and_return(:disconnected)
        @broker1.should_receive(:connected?).and_return(false)
        ha.__send__(:update_status, @broker1, true)
        connected.should == 0
        disconnected.should == 0
        @broker2.should_receive(:status).and_return(:disconnected)
        @broker2.should_receive(:connected?).and_return(false)
        ha.__send__(:update_status, @broker2, true)
        connected.should == 0
        disconnected.should == 1
      end

      it "should provide connection status callback only once when one-off is requested" do
        flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity, @address, @serializer,
                @exceptions, Hash, nil, nil).and_return(@broker).once
        ha = RightScale::HABrokerClient.new(@serializer)
        called = 0
        ha.connection_status(:one_off => 10) { |_| called += 1 }
        ha.__send__(:update_status, @broker, false)
        called.should == 1
        @broker.should_receive(:status).and_return(:disconnected)
        @broker.should_receive(:connected?).and_return(false)
        ha.__send__(:update_status, @broker, true)
        called.should == 1
      end

      it "should use connection status timer when one-off is requested" do
        flexmock(EM::Timer).should_receive(:new).and_return(@timer).once
        @timer.should_receive(:cancel).once
        flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity, @address, @serializer,
                @exceptions, Hash, nil, nil).and_return(@broker).once
        ha = RightScale::HABrokerClient.new(@serializer)
        called = 0
        ha.connection_status(:one_off => 10) { |_| called += 1 }
        ha.__send__(:update_status, @broker, false)
        called.should == 1
      end

      it "should give timeout connection status if one-off request times out" do
        flexmock(EM::Timer).should_receive(:new).and_return(@timer).and_yield.once
        @timer.should_receive(:cancel).never
        flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity, @address, @serializer,
                @exceptions, Hash, nil, nil).and_return(@broker).once
        ha = RightScale::HABrokerClient.new(@serializer)
        called = 0
        ha.connection_status(:one_off => 10) { |status| called += 1; status.should == :timeout }
        called.should == 1
      end

      it "should be able to have multiple connection status callbacks" do
        flexmock(RightScale::BrokerClient).should_receive(:new).with(@identity, @address, @serializer,
                @exceptions, Hash, nil, nil).and_return(@broker).once
        ha = RightScale::HABrokerClient.new(@serializer)
        called1 = 0
        called2 = 0
        ha.connection_status(:one_off => 10) { |_| called1 += 1 }
        ha.connection_status(:boundary => :all) { |_| called2 += 1 }
        ha.__send__(:update_status, @broker, false)
        @broker.should_receive(:status).and_return(:disconnected)
        @broker.should_receive(:connected?).and_return(false)
        ha.__send__(:update_status, @broker, true)
        called1.should == 1
        called2.should == 2
      end

    end # Monitoring

    describe "Closing" do

      it "should close all broker connections and execute block after all connections are closed" do
        @broker1.should_receive(:close).with(false, Proc).and_return(true).and_yield.once
        @broker2.should_receive(:close).with(false, Proc).and_return(true).and_yield.once
        @broker3.should_receive(:close).with(false, Proc).and_return(true).and_yield.once
        @broker4.should_receive(:close).with(false, Proc).and_return(true).and_yield.once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        called = 0
        ha.close { called += 1 }
        called.should == 1
      end

      it "should close broker connections when no block supplied" do
        @broker1.should_receive(:close).with(false, Proc).and_return(true).and_yield.once
        @broker2.should_receive(:close).with(false, Proc).and_return(true).and_yield.once
        @broker3.should_receive(:close).with(false, Proc).and_return(true).and_yield.once
        @broker4.should_receive(:close).with(false, Proc).and_return(true).and_yield.once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.close
      end

      it "should close all broker connections even if encounter an exception" do
        flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed to close/, Exception, :trace).once
        @broker1.should_receive(:close).and_return(true).and_yield.once
        @broker2.should_receive(:close).and_raise(Exception).once
        @broker3.should_receive(:close).and_return(true).and_yield.once
        @broker4.should_receive(:close).and_return(true).and_yield.once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        called = 0
        ha.close { called += 1 }
        called.should == 1
      end

      it "should close an individual broker connection" do
        @broker1.should_receive(:close).with(true).and_return(true).once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.close_one(@identity1)
      end

      it "should not propagate connection status change if requested not to" do
        @broker1.should_receive(:close).with(false).and_return(true).once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        ha.close_one(@identity1, propagate = false)
      end

      it "should close an individual broker connection and execute block if given" do
        @broker1.should_receive(:close).with(true, Proc).and_return(true).and_yield.once
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        called = 0
        ha.close_one(@identity1) { called += 1 }
        called.should == 1
      end

      it "should raise exception if unknown broker" do
        ha = RightScale::HABrokerClient.new(@serializer, :islands => @islands, :home_island => @home)
        lambda { ha.close_one("rs-broker-fifth-5672") }.should raise_error(Exception, /Cannot close unknown broker/)
      end

    end # Closing

  end # When

end # RightScale::HABrokerClient
