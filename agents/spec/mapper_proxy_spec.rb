require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')

describe RightScale::MapperProxy do
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
  
  describe "when requesting a message" do
    before do
      flexmock(AMQP).should_receive(:connect)
      @fanout = flexmock("fanout", :publish => true)
      @queue = flexmock("queue", :subscribe => {})
      @amq = flexmock("AMQueue", :queue => @queue, :fanout => @fanout)
      flexmock(MQ).should_receive(:new).and_return(@amq)
      RightScale::MapperProxy.new('mapperproxy', {})
      @instance = RightScale::MapperProxy.instance
    end
    
    it "should raise an error if mapper proxy is not initialized" do
      lambda {
        flexmock(@instance).should_receive(:identity).and_return nil
        @instance.request('/welcome/aboard', 'iZac'){|response|}
      }.should raise_error("Mapper proxy not initialized")
    end
    
    it "should create a request object" do
      @fanout.should_receive(:publish).with do |request|
        request = @instance.serializer.load(request)
        request.class.should == RightScale::RequestPacket
      end
      
      @instance.request('/welcome/aboard', 'iZac'){|response|}
    end
    
    it "should set correct attributes on the request message" do
      @fanout.should_receive(:publish).with do |request|
        request = @instance.serializer.load(request)
        request.token.should_not == nil
        request.persistent.should_not == true
        request.from.should == 'mapperproxy'
      end
      
      @instance.request('/welcome/aboard', 'iZac'){|response|}
    end
    
    it "should mark the message as persistent when the option is specified on the parameter" do
      @fanout.should_receive(:publish).with do |request|
        request = @instance.serializer.load(request)
        request.persistent.should == true
      end
      
      @instance.request('/welcome/aboard', 'iZac', :persistent => true){|response|}
    end
    
    it "should set the correct target if specified" do
      @fanout.should_receive(:publish).with do |request|
        request = @instance.serializer.load(request)
        request.target.should == 'my-target'
      end
      
      @instance.request('/welcome/aboard', 'iZac', :target => 'my-target'){|response|}
    end
    
    it "should mark the message as persistent when the option is set globally" do
      @instance.options[:persistent] = true
      @fanout.should_receive(:publish).with do |request|
        request = @instance.serializer.load(request)
        request.persistent.should == true
      end
      
      @instance.request('/welcome/aboard', 'iZac'){|response|}
    end

    it "should store the result handler" do
      result_handler = lambda {}
      flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return('abc')
      flexmock(@fanout).should_receive(:fanout)
      
      @instance.request('/welcome/aboard', 'iZac',{}, &result_handler)
      
      @instance.pending_requests['abc'][:result_handler].should == result_handler
    end
  end

  describe "when pushing a message" do
    before do
      flexmock(AMQP).should_receive(:connect)
      @fanout = flexmock("fanout", :publish => true)
      @queue = flexmock("queue", :subscribe => {})
      @amq = flexmock("AMQueue", :queue => @queue, :fanout => @fanout)
      flexmock(MQ).should_receive(:new).and_return(@amq)
      RightScale::MapperProxy.new('mapperproxy', {})
      @instance = RightScale::MapperProxy.instance
    end
    
    it "should raise an error if mapper proxy is not initialized" do
      lambda {
        flexmock(@instance).should_receive(:identity).and_return nil
        @instance.push('/welcome/aboard', 'iZac')
      }.should raise_error("Mapper proxy not initialized")
    end
    
    it "should create a push object" do
      @fanout.should_receive(:publish).with do |push|
        push = @instance.serializer.load(push)
        push.class.should == RightScale::PushPacket
      end
      
      @instance.push('/welcome/aboard', 'iZac')
    end
    
    it "should set the correct target if specified" do
      @fanout.should_receive(:publish).with do |push|
        push = @instance.serializer.load(push)
        push.target.should == 'my-target'
      end
      
      @instance.push('/welcome/aboard', 'iZac', :target => 'my-target')
    end
    
    it "should set correct attributes on the push message" do
      @fanout.should_receive(:publish).with do |push|
        push = @instance.serializer.load(push)
        push.token.should_not == nil
        push.persistent.should_not == true
        push.from.should == 'mapperproxy'
      end
      
      @instance.push('/welcome/aboard', 'iZac')
    end
    
    it "should mark the message as persistent when the option is specified on the parameter" do
      @fanout.should_receive(:publish).with do |push|
        push = @instance.serializer.load(push)
        push.persistent.should == true
      end
      
      @instance.push('/welcome/aboard', 'iZac', :persistent => true)
    end
    
    it "should mark the message as persistent when the option is set globally" do
      @instance.options[:persistent] = true
      @fanout.should_receive(:publish).with do |push|
        push = @instance.serializer.load(push)
        push.persistent.should == true
      end
      
      @instance.push('/welcome/aboard', 'iZac')
    end
  end
end
