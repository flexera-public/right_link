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

  before(:all) do
    @original_completed_file = RightScale::Dispatcher::Completed::COMPLETED_FILE
    file_path = File.join(RightScale::SpecHelpers::RIGHT_LINK_SPEC_HELPER_TEMP_PATH, "__completed_requests.js")
    RightScale::Dispatcher::Completed.const_set(:COMPLETED_FILE, file_path)
    @original_completed_file2 = RightScale::Dispatcher::Completed::COMPLETED_FILE2
    file_path = File.join(RightScale::SpecHelpers::RIGHT_LINK_SPEC_HELPER_TEMP_PATH, "__completed_requests2.js")
    RightScale::Dispatcher::Completed.const_set(:COMPLETED_FILE2, file_path)
  end

  before(:each) do
    flexmock(RightScale::RightLinkLog).should_receive(:error).never.by_default
    flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    @now = Time.at(1000000)
    flexmock(Time).should_receive(:now).and_return(@now).by_default
    @broker = flexmock("Broker", :subscribe => true, :publish => true).by_default
    @actor = Foo.new
    @registry = RightScale::ActorRegistry.new
    @registry.register(@actor, nil)
    @agent = flexmock("Agent", :identity => "agent", :broker => @broker, :registry => @registry, :options => {}).by_default
    @dispatcher = RightScale::Dispatcher.new(@agent)
    @dispatcher.em = EMMock
  end

  after(:each) do
    File.delete(RightScale::Dispatcher::Completed::COMPLETED_FILE,
                RightScale::Dispatcher::Completed::COMPLETED_FILE2) rescue nil
  end

  after(:all) do
    RightScale::Dispatcher::Completed.const_set(:COMPLETED_FILE, @original_completed_file)
    RightScale::Dispatcher::Completed.const_set(:COMPLETED_FILE2, @original_completed_file2)
  end

  describe "Completed cache" do

    before(:each) do
      @exceptions = flexmock("exceptions", :track => true)
      flexmock(RightScale::StatsHelper::ExceptionStats).should_receive(:new).and_return(@exceptions)
      @completed = RightScale::Dispatcher::Completed.new(@exceptions)
      @token1 = "token1"
      @token2 = "token2"
      @token3 = "token3"
    end

    context "when storing" do

      it "should store request token" do
        @completed.store(@token1)
        @completed.instance_variable_get(:@cache)[@token1].should == @now.to_i
        @completed.instance_variable_get(:@lru).should == [@token1]
      end

      it "should update lru list when store to existing entry" do
        @completed.store(@token1)
        @completed.instance_variable_get(:@cache)[@token1].should == @now.to_i
        @completed.instance_variable_get(:@lru).should == [@token1]
        @completed.store(@token2)
        @completed.instance_variable_get(:@cache)[@token2].should == @now.to_i
        @completed.instance_variable_get(:@lru).should == [@token1, @token2]
        flexmock(Time).should_receive(:now).and_return(@now += 10)
        @completed.store(@token1)
        @completed.instance_variable_get(:@cache)[@token1].should == @now.to_i
        @completed.instance_variable_get(:@lru).should == [@token2, @token1]
      end

      it "should remove old cache entries when store new one" do
        @completed.store(@token1)
        @completed.store(@token2)
        @completed.instance_variable_get(:@cache).keys.should == [@token1, @token2]
        @completed.instance_variable_get(:@lru).should == [@token1, @token2]
        flexmock(Time).should_receive(:now).and_return(@now += RightScale::Dispatcher::Completed::MAX_AGE + 1)
        @completed.store(@token3)
        @completed.instance_variable_get(:@cache).keys.should == [@token3]
        @completed.instance_variable_get(:@lru).should == [@token3]
      end

    end

    context "when fetching" do

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

    end

    context "when loading" do

      it "should load nothing if file does not exist" do
        @completed = RightScale::Dispatcher::Completed.new(@exceptions)
        @completed.size.should == 0
      end

      it "should load cache from disk but only store entries not exceeding max age" do
        @completed.store(@token1)
        @completed.store(@token2)
        flexmock(Time).should_receive(:now).and_return(@now += RightScale::Dispatcher::Completed::MAX_AGE + 1)
        @completed.store(@token3)
        @completed = RightScale::Dispatcher::Completed.new(@exceptions)
        @completed.size.should == 1
        @completed.instance_variable_get(:@cache)[@token3].should == @now.to_i
        @completed.instance_variable_get(:@lru).should == [@token3]
      end

      it "should recover cache from alternate file if exists" do
        @completed.store(@token1)
        @completed.store(@token2)
        flexmock(Time).should_receive(:now).and_return(@now += RightScale::Dispatcher::Completed::MAX_AGE + 1)
        @completed.store(@token3)
        File.rename(RightScale::Dispatcher::Completed::COMPLETED_FILE, RightScale::Dispatcher::Completed::COMPLETED_FILE2)
        @completed = RightScale::Dispatcher::Completed.new(@exceptions)
        @completed.size.should == 1
        @completed.instance_variable_get(:@cache)[@token3].should == @now.to_i
        @completed.instance_variable_get(:@lru).should == [@token3]
      end

      it "should delete alternate file if both files exist" do
        @completed.store(@token1)
        @completed.store(@token2)
        flexmock(Time).should_receive(:now).and_return(@now += RightScale::Dispatcher::Completed::MAX_AGE + 1)
        @completed.store(@token3)
        File.link(RightScale::Dispatcher::Completed::COMPLETED_FILE, RightScale::Dispatcher::Completed::COMPLETED_FILE2)
        @completed = RightScale::Dispatcher::Completed.new(@exceptions)
        @completed.size.should == 1
        @completed.instance_variable_get(:@cache)[@token3].should == @now.to_i
        @completed.instance_variable_get(:@lru).should == [@token3]
        File.exist?(RightScale::Dispatcher::Completed::COMPLETED_FILE2).should be_false
      end

      it "should log error if fail to load cache but should still finish initialization" do
        flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed loading completed cache/, Exception, :trace).once
        flexmock(File).should_receive(:exist?).and_raise(Exception)
        @completed = RightScale::Dispatcher::Completed.new(@exceptions)
        @completed.size.should == 0
      end

    end

    context "when persisting" do

      it "should persist request token" do
        data = JSON.dump("token" => @token1, "time" => @now.to_i)
        flexmock(@completed.instance_variable_get(:@file)).should_receive(:puts).with(data).once
        @completed.store(@token1)
      end

      it "should flush old data if exceed max age and minimum number of cache entries" do
        begin
          flexmock(Time).should_receive(:now).and_return(@now += RightScale::Dispatcher::Completed::MAX_AGE + 1)
          original_min_flush_size = RightScale::Dispatcher::Completed::MIN_FLUSH_SIZE
          RightScale::Dispatcher::Completed.const_set(:MIN_FLUSH_SIZE, 0)
          flexmock(@completed.instance_variable_get(:@file)).should_receive(:puts).once
          flexmock(@completed).should_receive(:flush).once
          @completed.store(@token1)
          @completed.instance_variable_get(:@persisted).should == 0
          @completed.instance_variable_get(:@last_flush).should == @now.to_i
        ensure
          RightScale::Dispatcher::Completed.const_set(:MIN_FLUSH_SIZE, original_min_flush_size)
        end
      end

      it "should log error if cannot persist but should still store" do
        flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed persisting completed request/, Exception, :trace).once
        flexmock(@completed.instance_variable_get(:@file)).should_receive(:puts).and_raise(Exception)
        @completed.store(@token1)
        @completed.instance_variable_get(:@cache)[@token1].should == @now.to_i
        @completed.instance_variable_get(:@lru).should == [@token1]
      end

    end

    context "when flushing" do

      it "should replace persisted data with current cache data" do
        @completed.store(@token1)
        @completed.store(@token2)
        flexmock(Time).should_receive(:now).and_return(@now += RightScale::Dispatcher::Completed::MAX_AGE + 1)
        @completed.store(@token3)
        File.open(RightScale::Dispatcher::Completed::COMPLETED_FILE, 'r') { |f| f.readlines.size.should == 3 }
        @completed.size.should == 1
        @completed.__send__(:flush)
        @completed.size.should == 1
        @completed.instance_variable_get(:@cache)[@token3].should == @now.to_i
        @completed.instance_variable_get(:@lru).should == [@token3]
        @completed.instance_variable_get(:@persisted).should == 1
        @completed.instance_variable_get(:@last_flush).should == @now.to_i
        File.exist?(RightScale::Dispatcher::Completed::COMPLETED_FILE2).should be_false
        File.open(RightScale::Dispatcher::Completed::COMPLETED_FILE, 'r') { |f| f.readlines.size.should == 1 }
      end

      it "should log error and reopen existing file if flush fails" do
        @completed.store(@token1)
        @completed.store(@token2)
        flexmock(Time).should_receive(:now).and_return(@now += RightScale::Dispatcher::Completed::MAX_AGE + 1)
        @completed.store(@token3)
        File.open(RightScale::Dispatcher::Completed::COMPLETED_FILE, 'r') { |f| f.readlines.size.should == 3 }
        @completed.size.should == 1
        flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed flushing old persisted data/, Exception, :trace).once
        flexmock(File).should_receive(:rename).and_raise(Exception)
        @completed.__send__(:flush)
        @completed.size.should == 1
        @completed.instance_variable_get(:@cache)[@token3].should == @now.to_i
        @completed.instance_variable_get(:@lru).should == [@token3]
        @completed.instance_variable_get(:@persisted).should == 0
        @completed.instance_variable_get(:@last_flush).should == @now.to_i
        File.exist?(RightScale::Dispatcher::Completed::COMPLETED_FILE2).should be_false
        File.open(RightScale::Dispatcher::Completed::COMPLETED_FILE, 'r') { |f| f.readlines.size.should == 3 }
        @completed.store(@token1)
        @completed.size.should == 2
        File.open(RightScale::Dispatcher::Completed::COMPLETED_FILE, 'r') { |f| f.readlines.size.should == 4 }
      end

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
    flexmock(RightScale::RightLinkLog).should_receive(:error).once
    req = RightScale::Request.new('/foo/i_kill_you', nil)
    flexmock(@actor).should_receive(:handle_exception).with(:i_kill_you, req, Exception).once
    @dispatcher.dispatch(req)
  end

  it "should call on_exception Procs defined in a subclass with the correct arguments" do
    flexmock(RightScale::RightLinkLog).should_receive(:error).once
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
    flexmock(RightScale::RightLinkLog).should_receive(:error).once
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
    req = RightScale::Push.new('/foo/bar', 'you', :expires_at => @now.to_i + 8)
    flexmock(Time).should_receive(:now).and_return(@now += 10)
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
    req = RightScale::Request.new('/foo/bar', 'you', :expires_at => @now.to_i + 8)
    flexmock(Time).should_receive(:now).and_return(@now += 10)
    @dispatcher.dispatch(req).should be_nil
  end

  it "should send error result instead of non-delivery if agent is below version 13" do
    # TODO Once have version info in packet
  end

  it "should not reject requests whose time-to-live has not expired" do
    flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
    @dispatcher = RightScale::Dispatcher.new(@agent)
    @dispatcher.em = EMMock
    req = RightScale::Request.new('/foo/bar', 'you', :expires_at => @now.to_i + 11)
    flexmock(Time).should_receive(:now).and_return(@now += 10)
    res = @dispatcher.dispatch(req)
    res.should(be_kind_of(RightScale::Result))
    res.token.should == req.token
    res.results.should == ['hello', 'you']
  end

  it "should not check age of requests with time-to-live check disabled" do
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
      @dispatcher.instance_variable_get(:@completed).should be_nil
      @dispatcher.dispatch(req).should_not be_nil
      EM.stop
    end
  end

  it "should return dispatch age of youngest unfinished request" do
    @dispatcher.em = EMMockNoCallback
    @dispatcher.dispatch_age.should be_nil
    @dispatcher.dispatch(RightScale::Push.new('/foo/bar', 'you'))
    @dispatcher.dispatch_age.should == 0
    @dispatcher.dispatch(RightScale::Request.new('/foo/bar', 'you'))
    flexmock(Time).should_receive(:now).and_return(@now += 100)
    @dispatcher.dispatch_age.should == 100
  end

  it "should return dispatch age of nil if all requests finished" do
    @dispatcher.dispatch_age.should be_nil
    @dispatcher.dispatch(RightScale::Request.new('/foo/bar', 'you'))
    flexmock(Time).should_receive(:now).and_return(@now += 100)
    @dispatcher.dispatch_age.should be_nil
  end

end # RightScale::Dispatcher
