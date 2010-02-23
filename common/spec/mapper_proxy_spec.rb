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

describe RightScale::MapperProxy do

  include FlexMock::ArgumentTypes

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
      @queue = flexmock("queue", :publish => true).by_default
      @amq = flexmock("AMQueue", :queue => @queue)
      flexmock(MQ).should_receive(:new).and_return(@amq)
      RightScale::MapperProxy.new('mapperproxy', {})
      @instance = RightScale::MapperProxy.instance
    end
    
    it "should raise an error if mapper proxy is not initialized" do
      lambda {
        flexmock(@instance).should_receive(:identity).and_return(nil).once
        @instance.request('/welcome/aboard', 'iZac'){|response|}
      }.should raise_error("Mapper proxy not initialized")
    end
    
    it "should create a request object" do
      @queue.should_receive(:publish).with(on do |request|
        request = @instance.serializer.load(request)
        request.class.should == RightScale::Request
      end).once
      
      @instance.request('/welcome/aboard', 'iZac'){|response|}
    end
    
    it "should set correct attributes on the request message" do
      @queue.should_receive(:publish).with(on do |request|
        request = @instance.serializer.load(request)
        request.token.should_not == nil
        request.persistent.should_not == true
        request.from.should == 'mapperproxy'
      end).once
      
      @instance.request('/welcome/aboard', 'iZac'){|response|}
    end
    
    it "should mark the message as persistent when the option is specified on the parameter" do
      @queue.should_receive(:publish).with(on do |request|
        request = @instance.serializer.load(request)
        request.persistent.should == true
      end).once
      
      @instance.request('/welcome/aboard', 'iZac', :persistent => true){|response|}
    end
    
    it "should set the correct target if specified" do
      @queue.should_receive(:publish).with(on do |request|
        request = @instance.serializer.load(request)
        request.target.should == 'my-target'
      end).once
      
      @instance.request('/welcome/aboard', 'iZac', :target => 'my-target'){|response|}
    end
    
    it "should mark the message as persistent when the option is set globally" do
      @instance.options[:persistent] = true
      @queue.should_receive(:publish).with(on do |request|
        request = @instance.serializer.load(request)
        request.persistent.should == true
      end).once
      
      @instance.request('/welcome/aboard', 'iZac'){|response|}
    end

    it "should store the result handler" do
      result_handler = lambda {}
      flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return('abc').once
      @instance.request('/welcome/aboard', 'iZac',{}, &result_handler)
      
      @instance.pending_requests['abc'][:result_handler].should == result_handler
    end
  end

  describe "when pushing a message" do
    before do
      flexmock(AMQP).should_receive(:connect)
      @queue = flexmock("queue", :publish => true).by_default
      @amq = flexmock("AMQueue", :queue => @queue)
      flexmock(MQ).should_receive(:new).and_return(@amq)
      RightScale::MapperProxy.new('mapperproxy', {})
      @instance = RightScale::MapperProxy.instance
    end
    
    it "should raise an error if mapper proxy is not initialized" do
      lambda {
        flexmock(@instance).should_receive(:identity).and_return(nil).once
        @instance.push('/welcome/aboard', 'iZac')
      }.should raise_error("Mapper proxy not initialized")
    end
    
    it "should create a push object" do
      @queue.should_receive(:publish).with(on do |push|
        push = @instance.serializer.load(push)
        push.class.should == RightScale::Push
      end).once
      
      @instance.push('/welcome/aboard', 'iZac')
    end
    
    it "should set the correct target if specified" do
      @queue.should_receive(:publish).with(on do |push|
        push = @instance.serializer.load(push)
        push.target.should == 'my-target'
      end).once
      
      @instance.push('/welcome/aboard', 'iZac', :target => 'my-target')
    end
    
    it "should set correct attributes on the push message" do
      @queue.should_receive(:publish).with(on do |push|
        push = @instance.serializer.load(push)
        push.token.should_not == nil
        push.persistent.should_not == true
        push.from.should == 'mapperproxy'
      end).once
      
      @instance.push('/welcome/aboard', 'iZac')
    end
    
    it "should mark the message as persistent when the option is specified on the parameter" do
      @queue.should_receive(:publish).with(on do |push|
        push = @instance.serializer.load(push)
        push.persistent.should == true
      end).once
      
      @instance.push('/welcome/aboard', 'iZac', :persistent => true)
    end
    
    it "should mark the message as persistent when the option is set globally" do
      @instance.options[:persistent] = true
      @queue.should_receive(:publish).with(on do |push|
        push = @instance.serializer.load(push)
        push.persistent.should == true
      end).once
      
      @instance.push('/welcome/aboard', 'iZac')
    end
  end
end
