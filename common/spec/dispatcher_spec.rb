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

class Foo
  include RightScale::Actor
  expose :bar, :index, :i_kill_you
  on_exception :handle_exception

  def index(payload)
    bar(payload)
  end

  def bar(payload)
    ['hello', payload]
  end
  
  def bar2(payload, deliverable)
    deliverable
  end

  def i_kill_you(payload)
    raise RuntimeError.new('I kill you!')
  end

  def handle_exception(method, deliverable, error)
  end
end

class Bar
  include RightScale::Actor
  expose :i_kill_you
  on_exception do |method, deliverable, error|
    @scope = self
    @called_with = [method, deliverable, error]
  end

  def i_kill_you(payload)
    raise RuntimeError.new('I kill you!')
  end
end

# No specs, simply ensures multiple methods for assigning on_exception callback,
# on_exception raises exception when called with an invalid argument.
class Doomed
  include RightScale::Actor
  on_exception do
  end
  on_exception lambda {}
  on_exception :doh
end

# Mock the EventMachine deferrer.
class EMMock
  def self.defer(op = nil, callback = nil)
    callback.call(op.call)
  end
end

describe "RightScale::Dispatcher" do

  before(:each) do
    flexmock(RightScale::RightLinkLog).should_receive(:info)
    flexmock(RightScale::RightLinkLog).should_receive(:error).by_default
    amq = flexmock('amq', :queue => flexmock('queue', :publish => nil))
    @actor = Foo.new
    @registry = RightScale::ActorRegistry.new
    @registry.register(@actor, nil)
    @dispatcher = RightScale::Dispatcher.new(amq, @registry, RightScale::Serializer.new(:marshal), '0xfunkymonkey', {})
    @dispatcher.evmclass = EMMock
  end

  it "should dispatch a request" do
    req = RightScale::Request.new('/foo/bar', 'you')
    res = @dispatcher.dispatch(req)
    res.should(be_kind_of(RightScale::Result))
    res.token.should == req.token
    res.results.should == ['hello', 'you']
  end

  it "should dispatch the deliverable to actions that accept it" do
    req = RightScale::Request.new('/foo/bar2', 'you')
    res = @dispatcher.dispatch(req)
    res.should(be_kind_of(RightScale::Result))
    res.token.should == req.token
    res.results.should == req
  end
  
  it "should dispatch a request to the default action" do
    req = RightScale::Request.new('/foo', 'you')
    res = @dispatcher.dispatch(req)
    res.should(be_kind_of(RightScale::Result))
    res.token.should == req.token
    res.results.should == ['hello', 'you']
  end

  it "should handle custom prefixes" do
    @registry.register(Foo.new, 'umbongo')
    req = RightScale::Request.new('/umbongo/bar', 'you')
    res = @dispatcher.dispatch(req)
    res.should(be_kind_of(RightScale::Result))
    res.token.should == req.token
    res.results.should == ['hello', 'you']
  end

  it "should call the on_exception callback if something goes wrong" do
    req = RightScale::Request.new('/foo/i_kill_you', nil)
    flexmock(@actor).should_receive(:handle_exception).with(:i_kill_you, req, Exception).once
    @dispatcher.dispatch(req)
  end

  it "should call on_exception Procs defined in a subclass with the correct arguments" do
    actor = Bar.new
    @registry.register(actor, nil)
    req = RightScale::Request.new('/bar/i_kill_you', nil)
    @dispatcher.dispatch(req)
    called_with = actor.instance_variable_get("@called_with")
    called_with[0].should == :i_kill_you
    called_with[1].should == req
    called_with[2].should be_kind_of(RuntimeError)
    called_with[2].message.should == 'I kill you!'
  end

  it "should call on_exception Procs defined in a subclass in the scope of the actor" do
    actor = Bar.new
    @registry.register(actor, nil)
    req = RightScale::Request.new('/bar/i_kill_you', nil)
    @dispatcher.dispatch(req)
    actor.instance_variable_get("@scope").should == actor
  end

  it "should log error if something goes wrong" do
    RightScale::RightLinkLog.should_receive(:error).once
    req = RightScale::Request.new('/foo/i_kill_you', nil)
    @dispatcher.dispatch(req)
  end

  it "should reject requests that are too old" do
    
  end

end # RightScale::Dispatcher
