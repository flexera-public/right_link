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

# Mock the EventMachine deferrer but do not do callback.
class EMMockNoCallback
  def self.defer(op = nil, callback = nil)
    op.call
  end
end

describe "RightScale::Dispatcher" do

  include FlexMock::ArgumentTypes

  before(:each) do
    flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    flexmock(RightScale::RightLinkLog).should_receive(:error).by_default
    @broker = flexmock("Broker", :subscribe => true, :publish => true).by_default
    @actor = Foo.new
    @registry = RightScale::ActorRegistry.new
    @registry.register(@actor, nil)
    @agent = flexmock("Agent", :identity => "agent", :broker => @broker, :registry => @registry, :options => {}).by_default
    @dispatcher = RightScale::Dispatcher.new(@agent)
    @dispatcher.em = EMMock
  end

  describe "Completed" do

    before(:each) do
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
      @completed = RightScale::Dispatcher::Completed.new
      @token1 = "token1"
      @token2 = "token2"
      @token3 = "token3"
    end

    it "should store request token" do
      @completed.store(@token1)
      @completed.instance_variable_get(:@cache)[@token1].should == 1000000
      @completed.instance_variable_get(:@lru).should == [@token1]
    end

    it "should update lru list when store to existing entry" do
      @completed.store(@token1)
      @completed.instance_variable_get(:@cache)[@token1].should == 1000000
      @completed.instance_variable_get(:@lru).should == [@token1]
      @completed.store(@token2)
      @completed.instance_variable_get(:@cache)[@token2].should == 1000000
      @completed.instance_variable_get(:@lru).should == [@token1, @token2]
      flexmock(Time).should_receive(:now).and_return(Time.at(1000010))
      @completed.store(@token1)
      @completed.instance_variable_get(:@cache)[@token1].should == 1000010
      @completed.instance_variable_get(:@lru).should == [@token2, @token1]
    end

    it "should remove old cache entries when store new one" do
      @completed.store(@token1)
      @completed.store(@token2)
      @completed.instance_variable_get(:@cache).keys.should == [@token1, @token2]
      @completed.instance_variable_get(:@lru).should == [@token1, @token2]
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000 + RightScale::Dispatcher::Completed::MAX_AGE + 1))
      @completed.store(@token3)
      @completed.instance_variable_get(:@cache).keys.should == [@token3]
      @completed.instance_variable_get(:@lru).should == [@token3]
    end

    it "should fetch request and make it the most recently used" do
      @completed.store(@token1)
      @completed.store(@token2)
      @completed.instance_variable_get(:@lru).should == [@token1, @token2]
      @completed.fetch(@token1).should be_true
      @completed.instance_variable_get(:@lru).should == [@token2, @token1]
    end

    it "should return false if fetch non-existent request" do
      @completed.fetch(@token1).should be_false
      @completed.store(@token1)
      @completed.fetch(@token1).should be_true
      @completed.fetch(@token2).should be_false
    end

  end # Completed

  it "should dispatch a request" do
    req = RightScale::Request.new('/foo/bar', 'you', :token => 'token')
    res = @dispatcher.dispatch(req)
    res.should(be_kind_of(RightScale::Result))
    res.token.should == 'token'
    res.results.should == ['hello', 'you']
  end

  it "should dispatch a request to the default action" do
    req = RightScale::Request.new('/foo', 'you', :token => 'token')
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

  it "should reject requests whose time-to-live has expired" do
    flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with(on {|arg| arg =~ /REJECT EXPIRED.*TTL 2 sec ago/})
    @broker.should_receive(:publish).never
    @dispatcher = RightScale::Dispatcher.new(@agent)
    @dispatcher.em = EMMock
    req = RightScale::Push.new('/foo/bar', 'you', :expires_at => 1000008)
    flexmock(Time).should_receive(:now).and_return(Time.at(1000010))
    @dispatcher.dispatch(req).should be_nil
  end

  it "should send non-delivery result if Request is rejected because its time-to-live has expired" do
    flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with(on {|arg| arg =~ /REJECT EXPIRED/})
    @broker.should_receive(:publish).with(Hash, on {|arg| arg.class == RightScale::Result &&
                                                          arg.results.non_delivery? &&
                                                          arg.results.content == RightScale::OperationResult::TTL_EXPIRATION},
                                          hsh(:persistent => true, :mandatory => true)).once
    @dispatcher = RightScale::Dispatcher.new(@agent)
    @dispatcher.em = EMMock
    req = RightScale::Request.new('/foo/bar', 'you', :expires_at => 1000008)
    flexmock(Time).should_receive(:now).and_return(Time.at(1000010))
    @dispatcher.dispatch(req).should be_nil
  end

  it "should send error result instead of non-delivery if agent is below version 13" do
    # TODO Once have version info in packet
  end

  it "should not reject requests whose time-to-live has not expired" do
    flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
    @dispatcher = RightScale::Dispatcher.new(@agent)
    @dispatcher.em = EMMock
    req = RightScale::Request.new('/foo/bar', 'you', :expires_at => 1000011)
    flexmock(Time).should_receive(:now).and_return(Time.at(1000010))
    res = @dispatcher.dispatch(req)
    res.should(be_kind_of(RightScale::Result))
    res.token.should == req.token
    res.results.should == ['hello', 'you']
  end

  it "should not check age of requests with time-to-live check disabled" do
    flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
    @dispatcher = RightScale::Dispatcher.new(@agent)
    @dispatcher.em = EMMock
    req = RightScale::Request.new('/foo/bar', 'you', :expires_at => 0)
    res = @dispatcher.dispatch(req)
    res.should(be_kind_of(RightScale::Result))
    res.token.should == req.token
    res.results.should == ['hello', 'you']
  end

  it "should reject duplicate requests" do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with(on {|arg| arg =~ /REJECT DUP/})
    EM.run do
      @agent.should_receive(:options).and_return(:dup_check => true)
      @dispatcher = RightScale::Dispatcher.new(@agent)
      req = RightScale::Request.new('/foo/bar', 'you', :token => "try")
      @dispatcher.instance_variable_get(:@completed).store(req.token)
      @dispatcher.dispatch(req).should be_nil
      EM.stop
    end
  end

  it "should reject duplicate retry requests" do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with(on {|arg| arg =~ /REJECT RETRY DUP/})
    EM.run do
      @agent.should_receive(:options).and_return(:dup_check => true)
      @dispatcher = RightScale::Dispatcher.new(@agent)
      req = RightScale::Request.new('/foo/bar', 'you', :token => "try")
      req.tries.concat(["try1", "try2"])
      @dispatcher.instance_variable_get(:@completed).store("try2")
      @dispatcher.dispatch(req).should be_nil
      EM.stop
    end
  end

  it "should not reject non-duplicate requests" do
    EM.run do
      @agent.should_receive(:options).and_return(:dup_check => true)
      @dispatcher = RightScale::Dispatcher.new(@agent)
      req = RightScale::Request.new('/foo/bar', 'you', :token => "try")
      req.tries.concat(["try1", "try2"])
      @dispatcher.instance_variable_get(:@completed).store("try3")
      @dispatcher.dispatch(req).should_not be_nil
      EM.stop
    end
  end

  it "should not check for duplicates if dup_check disabled" do
    EM.run do
      @dispatcher = RightScale::Dispatcher.new(@agent)
      req = RightScale::Request.new('/foo/bar', 'you', :token => "try")
      req.tries.concat(["try1", "try2"])
      @dispatcher.instance_variable_get(:@completed).store("try2")
      @dispatcher.dispatch(req).should_not be_nil
      EM.stop
    end
  end

  it "should return dispatch age of youngest unfinished request" do
    @dispatcher.em = EMMockNoCallback
    flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
    @dispatcher.dispatch_age.should be_nil
    @dispatcher.dispatch(RightScale::Push.new('/foo/bar', 'you'))
    @dispatcher.dispatch_age.should == 0
    @dispatcher.dispatch(RightScale::Request.new('/foo/bar', 'you'))
    flexmock(Time).should_receive(:now).and_return(Time.at(1000100))
    @dispatcher.dispatch_age.should == 100
  end

  it "should return dispatch age of nil if all requests finished" do
    flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
    @dispatcher.dispatch_age.should be_nil
    @dispatcher.dispatch(RightScale::Request.new('/foo/bar', 'you'))
    flexmock(Time).should_receive(:now).and_return(Time.at(1000100))
    @dispatcher.dispatch_age.should be_nil
  end

end # RightScale::Dispatcher
