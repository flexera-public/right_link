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

def run_in_em(stop_event_loop = true)
  EM.run do
    yield
    EM.stop_event_loop if stop_event_loop
  end
end

describe RightScale::Agent do

  include FlexMock::ArgumentTypes

  describe "Default Option" do

    before(:all) do
      flexmock(RightScale::RightLinkLog).should_receive(:error).never.by_default
      flexmock(EM).should_receive(:add_periodic_timer)
      flexmock(EM).should_receive(:next_tick).and_yield
      flexmock(EM).should_receive(:add_timer).and_yield
      @timer = flexmock("timer")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      @timer.should_receive(:cancel)
      @broker = flexmock("broker", :subscribe => ["b1"], :publish => ["b1"], :prefetch => true,
                         :all => ["b1"], :connected => ["b1"], :failed => [], :close_one => true,
                         :non_delivery => true).by_default
      @broker.should_receive(:connection_status).and_yield(:connected)
      flexmock(RightScale::HABrokerClient).should_receive(:new).and_return(@broker)
      flexmock(RightScale::PidFile).should_receive(:new).
              and_return(flexmock("pid file", :check=>true, :write=>true, :remove=>true))
      @identity = "rs-instance-123-1"
      @agent = RightScale::Agent.start(:identity => @identity)
    end

    after(:each) do
      FileUtils.rm_rf(File.normalize_path(File.join(@agent.options[:root], 'config.yml'))) if @agent
    end

    it "for daemonize is false" do
      @agent.options.should include(:daemonize)
      @agent.options[:daemonize].should == false
    end

    it "for console is false" do
      @agent.options.should include(:console)
      @agent.options[:console].should == false
    end

    it "for user is agent" do
      @agent.options.should include(:user)
      @agent.options[:user].should == "agent"
    end

    it "for pass(word) is testing" do
      @agent.options.should include(:pass)
      @agent.options[:pass].should == "testing"
    end

    it "for secure is false" do
      @agent.options.should include(:secure)
      @agent.options[:secure].should == false
    end

    it "for log_level is info" do
      @agent.options.should include(:log_level)
      @agent.options[:log_level].should == :info
    end

    it "for vhost is /right_net" do
      @agent.options.should include(:vhost)
      @agent.options[:vhost].should == "/right_net"
    end

    it "for root is #{Dir.pwd}" do
      @agent.options.should include(:root)
      @agent.options[:root].should == Dir.pwd
    end

  end

  describe "Options from config.yml" do

    before(:all) do
      @agent = RightScale::Agent.start
    end

    after(:each) do
      FileUtils.rm_rf(File.normalize_path(File.join(@agent.options[:root], 'config.yml'))) if @agent
    end
 
  end

  describe "Passed in Options" do

    before(:each) do
      flexmock(RightScale::RightLinkLog).should_receive(:error).never.by_default
      flexmock(EM).should_receive(:add_periodic_timer)
      flexmock(EM).should_receive(:next_tick).and_yield
      flexmock(EM).should_receive(:add_timer).and_yield
      @timer = flexmock("timer")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      @timer.should_receive(:cancel)
      @broker = flexmock("broker", :subscribe => ["b1"], :publish => ["b1"], :prefetch => true,
                         :connected => ["b1"], :failed => [], :all => ["b0", "b1"],
                         :non_delivery => true).by_default
      @broker.should_receive(:connection_status).and_yield(:connected)
      flexmock(RightScale::HABrokerClient).should_receive(:new).and_return(@broker)
      flexmock(RightScale::PidFile).should_receive(:new).
              and_return(flexmock("pid file", :check=>true, :write=>true, :remove=>true))
      @identity = "rs-instance-123-1"
      @agent = nil
    end

    after(:each) do
      FileUtils.rm_rf(File.normalize_path(File.join(@agent.options[:root], 'config.yml'))) if @agent
    end

    # TODO figure out how to stub call to daemonize
    # it "for daemonize should override default (false)" do
    #   agent = RightScale::Agent.start(:daemonize => true)
    #   agent.options.should include(:daemonize)
    #   agent.options[:daemonize].should == true
    # end

    # TODO figure out how to avoid console output
    # it "for console should override default (false)" do
    #   @agent = RightScale::Agent.start(:console => true, :identity => @identity)
    #   @agent.options.should include(:console)
    #   @agent.options[:console].should == true
    # end

    it "for user should override default (agent)" do
      @agent = RightScale::Agent.start(:user => "me", :identity => @identity)
      @agent.options.should include(:user)
      @agent.options[:user].should == "me"
    end

    it "for pass(word) should override default (testing)" do
      @agent = RightScale::Agent.start(:pass => "secret", :identity => @identity)
      @agent.options.should include(:pass)
      @agent.options[:pass].should == "secret"
    end

    it "for secure should override default (false)" do
      @agent = RightScale::Agent.start(:secure => true, :identity => @identity)
      @agent.options.should include(:secure)
      @agent.options[:secure].should == true
    end

    it "for host should override default (localhost)" do
      @agent = RightScale::Agent.start(:host => "127.0.0.1", :identity => @identity)
      @agent.options.should include(:host)
      @agent.options[:host].should == "127.0.0.1"
    end

    it "for log_dir" do
      # testing path, remove it before the test to verify the directory is
      # actually created
      test_log_path = File.normalize_path(File.join(Dir.tmpdir, "right_net", "testing"))
      FileUtils.rm_rf(test_log_path)

      @agent = RightScale::Agent.start(:log_dir => File.normalize_path(File.join(Dir.tmpdir, "right_net", "testing")),
                                       :identity => @identity)

      # passing log_dir will cause log_path to be set to the same value and the
      # directory wil be created
      @agent.options.should include(:log_dir)
      @agent.options[:log_dir].should == test_log_path

      @agent.options.should include(:log_path)
      @agent.options[:log_path].should == test_log_path

      File.directory?(@agent.options[:log_path]).should == true
    end

    it "for log_level should override default (info)" do
      @agent = RightScale::Agent.start(:log_level => :debug, :identity => @identity)
      @agent.options.should include(:log_level)
      @agent.options[:log_level].should == :debug
    end

    it "for vhost should override default (/right_net)" do
      @agent = RightScale::Agent.start(:vhost => "/virtual_host", :identity => @identity)
      @agent.options.should include(:vhost)
      @agent.options[:vhost].should == "/virtual_host"
    end

    it "for ping_time should override default (15)" do
      @agent = RightScale::Agent.start(:ping_time => 5, :identity => @identity)
      @agent.options.should include(:ping_time)
      @agent.options[:ping_time].should == 5
    end

    it "for root should override default (#{File.normalize_path(File.join(File.dirname(__FILE__), '..'))})" do
      @agent = RightScale::Agent.start(:root => File.normalize_path(File.dirname(__FILE__)),
                                       :identity => @identity)
      @agent.options.should include(:root)
      @agent.options[:root].should == File.normalize_path(File.dirname(__FILE__))
    end

    it "for a single tag should result in the agent's tags being set" do
      @agent = RightScale::Agent.start(:tag => "sample_tag", :identity => @identity)
      @agent.tags.should include("sample_tag")
    end

    it "for multiple tags should result in the agent's tags being set" do
      @agent = RightScale::Agent.start(:tag => ["sample_tag_1", "sample_tag_2"], :identity => @identity)
      @agent.tags.should include("sample_tag_1")
      @agent.tags.should include("sample_tag_2")
    end
    
    it "for threadpool_size" do
      @agent = RightScale::Agent.start(:threadpool_size => 5, :identity => @identity)
      @agent.dispatcher.em.threadpool_size.should == 5
    end
    
  end

  describe "" do

    before(:each) do
      flexmock(RightScale::RightLinkLog).should_receive(:error).never.by_default
      flexmock(EM).should_receive(:add_periodic_timer)
      flexmock(EM).should_receive(:next_tick).and_yield
      flexmock(EM).should_receive(:add_timer).and_yield
      @timer = flexmock("timer")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).by_default
      @timer.should_receive(:cancel).by_default
      @broker_id = "rs-broker-123-1"
      @broker_ids = ["rs-broker-123-1", "rs-broker-123-2"]
      @broker = flexmock("broker", :subscribe => @broker_ids, :publish => @broker_ids.first(1), :prefetch => true,
                         :all => @broker_ids, :connected => @broker_ids.first(1), :failed => @broker_ids.last(1),
                         :unusable => @broker_ids.last(1), :close_one => true, :non_delivery => true,
                         :stats => "", :identity_parts => ["123", 2, 1, 1, nil], :status => "status",
                         :hosts => ["123"], :ports => [1, 2], :get => true, :alias_ => "b1",
                         :aliases => ["b1"]).by_default
      @broker.should_receive(:connection_status).and_yield(:connected)
      flexmock(RightScale::HABrokerClient).should_receive(:new).and_return(@broker)
      flexmock(RightScale::PidFile).should_receive(:new).
              and_return(flexmock("pid file", :check=>true, :write=>true, :remove=>true))
      @mapper_proxy = flexmock("mapper_proxy", :pending_requests => [], :request_age => nil,
                               :message_received => true, :stats => "").by_default
      flexmock(RightScale::MapperProxy).should_receive(:new).and_return(@mapper_proxy)
      @dispatcher = flexmock("dispatcher", :dispatch_age => nil, :dispatch => true, :stats => "").by_default
      flexmock(RightScale::Dispatcher).should_receive(:new).and_return(@dispatcher)
      @identity = "rs-instance-123-1"
    end

    after(:each) do
      FileUtils.rm_rf(File.normalize_path(File.join(@agent.options[:root], 'config.yml'))) if @agent
    end

    describe "Setting up queues" do

      it "should subscribe to identity queue using identity exchange" do
        run_in_em do
          @broker.should_receive(:subscribe).with(hsh(:name => @identity), nil, Hash, Proc).and_return(@broker_ids).once
          @agent = RightScale::Agent.start(:user => "tester", :identity => @identity)
        end
      end

      it "should try to finish setup by connecting to failed brokers when check status" do
        run_in_em do
          @broker.should_receive(:subscribe).with(hsh(:name => @identity), nil, hsh(:brokers => nil), Proc).
                                             and_return(@broker_ids.first(1)).once
          @agent = RightScale::Agent.start(:user => "tester", :identity => @identity)
          @agent.instance_variable_get(:@remaining_setup).should == {:setup_identity_queue => @broker_ids.last(1)}
          @mapper_proxy.should_receive(:send_push).with("/registrar/connect", {:agent_identity => @identity, :host => "123",
                                                                               :port => 2, :id => 1, :priority => 1}).once
          @agent.__send__(:check_status)
        end
      end

      it "should try to connect to broker when requested" do
        run_in_em do
          @broker.should_receive(:subscribe).with(hsh(:name => @identity), nil, hsh(:brokers => nil), Proc).
                                             and_return(@broker_ids.first(1)).once
          @agent = RightScale::Agent.start(:user => "tester", :identity => @identity)
          @broker.should_receive(:connect).with("123", 2, 1, 1, nil, false, Proc).once
          @agent.connect("123", 2, 1, 1)
        end
      end

      it "should setup queues and update configuration when successfully connect to broker" do
        run_in_em do
          @broker.should_receive(:subscribe).with(hsh(:name => @identity), nil, hsh(:brokers => nil), Proc).
                                             and_return(@broker_ids.first(1)).once
          @agent = RightScale::Agent.start(:user => "tester", :identity => @identity)
          @broker.should_receive(:connect).with("123", 2, 1, 1, nil, false, Proc).and_yield(@broker_ids.last).once
          @broker.should_receive(:subscribe).with(hsh(:name => @identity), nil, hsh(:brokers => @broker_ids.last(1)), Proc).
                                             and_return(@broker_ids.last(1)).once
          flexmock(@agent).should_receive(:update_configuration).with(:host => ["123"], :port => [1, 2]).and_return(true).once
          @agent.connect("123", 2, 1, 1)
        end
      end

      it "should log error if fail to connect to broker" do
        run_in_em do
          @broker.should_receive(:subscribe).with(hsh(:name => @identity), nil, hsh(:brokers => nil), Proc).
                                             and_return(@broker_ids.first(1)).once
          @agent = RightScale::Agent.start(:user => "tester", :identity => @identity)
          @broker.should_receive(:connect).with("123", 2, 1, 1, nil, false, Proc).and_yield(@broker_ids.last).once
          @broker.should_receive(:connection_status).and_yield(:failed)
          flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed to connect to broker/).once
          flexmock(@agent).should_receive(:update_configuration).never
          @agent.connect("123", 2, 1, 1)
        end
      end

      it "should disconnect from broker when requested" do
        run_in_em do
          @broker.should_receive(:connected).and_return(@broker_ids)
          @broker.should_receive(:failed).and_return([])
          @broker.should_receive(:subscribe).with(hsh(:name => @identity), nil, hsh(:brokers => nil), Proc).
                                             and_return(@broker_ids).once
          @agent = RightScale::Agent.start(:user => "tester", :identity => @identity)
          @broker.should_receive(:close_one).with(@broker_ids.last).once
          @agent.disconnect("123", 2)
        end
      end

      it "should remove broker from configuration if requested" do
        run_in_em do
          @broker.should_receive(:connected).and_return(@broker_ids)
          @broker.should_receive(:failed).and_return([])
          @broker.should_receive(:subscribe).with(hsh(:name => @identity), nil, hsh(:brokers => nil), Proc).
                                             and_return(@broker_ids).once
          @agent = RightScale::Agent.start(:user => "tester", :identity => @identity)
          @broker.should_receive(:remove).with("123", 2, Proc).and_yield(@broker_ids.last).once
          @broker.should_receive(:ports).and_return([1])
          flexmock(@agent).should_receive(:update_configuration).with(:host => ["123"], :port => [1]).and_return(true).once
          @agent.disconnect("123", 2, remove = true)
        end
      end

      it "should not disconnect broker if it is the last connected broker" do
        run_in_em do
          @broker.should_receive(:subscribe).with(hsh(:name => @identity), nil, hsh(:brokers => nil), Proc).
                                             and_return(@broker_ids.first(1)).once
          @agent = RightScale::Agent.start(:user => "tester", :identity => @identity)
          @broker.should_receive(:remove).never
          @broker.should_receive(:close_one).never
          flexmock(@agent).should_receive(:update_configuration).never
          flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Not disconnecting.*last connected broker/).once
          @agent.disconnect("123", 1)
        end
      end

      it "should declare broker connection unusable if requested to do so" do
        run_in_em do
          @broker.should_receive(:subscribe).with(hsh(:name => @identity), nil, Hash, Proc).and_return(@broker_ids).once
          @agent = RightScale::Agent.start(:user => "tester", :identity => @identity)
          @broker.should_receive(:declare_unusable).with(@broker_ids.last(1)).once
          @agent.connect_failed(@broker_ids.last(1))
        end
      end

      it "should not declare a broker connection unusable if currently connected" do
        run_in_em do
          @broker.should_receive(:subscribe).with(hsh(:name => @identity), nil, Hash, Proc).and_return(@broker_ids).once
          @agent = RightScale::Agent.start(:user => "tester", :identity => @identity)
          @broker.should_receive(:declare_unusable).with([]).once
          @agent.connect_failed(@broker_ids.first(1))
        end
      end

    end

    describe "Handling messages" do
  
      it "should use dispatcher to handle requests" do
        run_in_em do
          request = RightScale::Request.new("/foo/bar", "payload")
          @broker.should_receive(:subscribe).with(hsh(:name => @identity), nil, Hash, Proc).
                                             and_return(@broker_ids).and_yield(@broker_id, request).once
          @dispatcher.should_receive(:dispatch).with(request).once
          @agent = RightScale::Agent.start(:user => "tester", :identity => @identity)
        end
      end

      it "should use mapper proxy to handle results" do
        run_in_em do
          result = RightScale::Result.new("token", "to", "results", "from")
          @broker.should_receive(:subscribe).with(hsh(:name => @identity), nil, Hash, Proc).
                                             and_return(@broker_ids).and_yield(@broker_id, result).once
          @mapper_proxy.should_receive(:handle_response).with(result).once
          @agent = RightScale::Agent.start(:user => "tester", :identity => @identity)
        end
      end

      it "should notify mapper proxy when a message is received" do
        run_in_em do
          result = RightScale::Result.new("token", "to", "results", "from")
          @broker.should_receive(:subscribe).with(hsh(:name => @identity), nil, Hash, Proc).
                                             and_return(@broker_ids).and_yield(@broker_id, result).once
          @mapper_proxy.should_receive(:handle_response).with(result).once
          @mapper_proxy.should_receive(:message_received).once
          @agent = RightScale::Agent.start(:user => "tester", :identity => @identity)
        end
      end

    end

    describe "Terminating" do

      it "should close unusable broker connections at start of termination" do
        @broker.should_receive(:unusable).and_return(["rs-broker-123-1"]).once
        @broker.should_receive(:close_one).with("rs-broker-123-1", false).once
        run_in_em do
          @agent = RightScale::Agent.new(:user => "me", :identity => @identity)
          @agent.run
          @agent.terminate
        end
      end

      it "should wait to terminate if there are recent unfinished requests" do
        @mapper_proxy.should_receive(:pending_requests).and_return(["request"]).once
        @mapper_proxy.should_receive(:request_age).and_return(10).once
        @dispatcher.should_receive(:dispatch_age).and_return(nil).once
        flexmock(EM::Timer).should_receive(:new).with(20, Proc).and_return(@timer).once
        run_in_em do
          @agent = RightScale::Agent.new(:user => "me", :identity => @identity)
          @agent.run
          @agent.terminate
        end
      end

      it "should wait to terminate if there are recent dispatches" do
        @mapper_proxy.should_receive(:pending_requests).and_return([]).once
        @mapper_proxy.should_receive(:request_age).and_return(nil).once
        @dispatcher.should_receive(:dispatch_age).and_return(20).and_return(@timer).once
        flexmock(EM::Timer).should_receive(:new).with(10, Proc).once
        run_in_em do
          @agent = RightScale::Agent.new(:user => "me", :identity => @identity)
          @agent.run
          @agent.terminate
        end
      end

      it "should wait to terminate if there are recent unfinished requests or recent dispatches" do
        @mapper_proxy.should_receive(:pending_requests).and_return(["request"]).once
        @mapper_proxy.should_receive(:request_age).and_return(21).once
        @dispatcher.should_receive(:dispatch_age).and_return(22).once
        flexmock(EM::Timer).should_receive(:new).with(9, Proc).and_return(@timer).once
        run_in_em do
          @agent = RightScale::Agent.new(:user => "me", :identity => @identity)
          @agent.run
          @agent.terminate
        end
      end

      it "should log that terminating and then log the reason for waiting to terminate" do
        @mapper_proxy.should_receive(:pending_requests).and_return(["request"]).once
        @mapper_proxy.should_receive(:request_age).and_return(21).once
        @dispatcher.should_receive(:dispatch_age).and_return(22).once
        flexmock(EM::Timer).should_receive(:new).with(9, Proc).and_return(@timer).once
        run_in_em do
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Agent rs-instance-123-1 with actors/).once
          @agent = RightScale::Agent.new(:user => "me", :identity => @identity)
          @agent.run
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Agent rs-instance-123-1 terminating/).once
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Termination waiting 9 seconds for/).once
          @agent.terminate
        end
      end

      it "should not log reason for waiting to terminate if no need to wait" do
        @mapper_proxy.should_receive(:pending_requests).and_return([]).once
        @mapper_proxy.should_receive(:request_age).and_return(nil).once
        @dispatcher.should_receive(:dispatch_age).and_return(nil).once
        flexmock(EM::Timer).should_receive(:new).with(0, Proc).and_return(@timer).once
        run_in_em do
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Agent rs-instance-123-1 with actors/).once
          @agent = RightScale::Agent.new(:user => "me", :identity => @identity)
          @agent.run
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Agent rs-instance-123-1 terminating/).once
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Termination waiting/).never
          @agent.terminate
        end
      end

      it "should continue with termination after waiting and log that continuing" do
        @mapper_proxy.should_receive(:pending_requests).and_return(["request"]).twice
        @mapper_proxy.should_receive(:request_age).and_return(10).twice
        @mapper_proxy.should_receive(:dump_requests).and_return(["request"]).once
        @dispatcher.should_receive(:dispatch_age).and_return(10).once
        @broker.should_receive(:close).once
        flexmock(EM::Timer).should_receive(:new).with(20, Proc).and_return(@timer).and_yield.once
        run_in_em do
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Agent rs-instance-123-1 with actors/).once
          @agent = RightScale::Agent.new(:user => "me", :identity => @identity)
          @agent.run
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Agent rs-instance-123-1 terminating/).once
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Termination waiting/).once
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Continuing with termination/).once
          flexmock(RightScale::RightLinkLog).should_receive(:info).with(/The following 1 request/).once
          @agent.terminate
        end
      end

      it "should execute block after all brokers have been closed" do
        @mapper_proxy.should_receive(:pending_requests).and_return(["request"]).twice
        @mapper_proxy.should_receive(:request_age).and_return(10).twice
        @mapper_proxy.should_receive(:dump_requests).and_return(["request"]).once
        @dispatcher.should_receive(:dispatch_age).and_return(10).once
        @broker.should_receive(:close).and_yield.once
        flexmock(EM::Timer).should_receive(:new).with(20, Proc).and_return(@timer).and_yield.once
        run_in_em do
          @agent = RightScale::Agent.new(:user => "me", :identity => @identity)
          @agent.run
          called = 0
          @agent.terminate { called += 1 }
          called.should == 1
        end
      end

      it "should stop EM if no block specified" do
        @mapper_proxy.should_receive(:pending_requests).and_return(["request"]).twice
        @mapper_proxy.should_receive(:request_age).and_return(10).twice
        @mapper_proxy.should_receive(:dump_requests).and_return(["request"]).once
        @dispatcher.should_receive(:dispatch_age).and_return(10).once
        @broker.should_receive(:close).once
        flexmock(EM::Timer).should_receive(:new).with(20, Proc).and_return(@timer).and_yield.once
        run_in_em(stop_event_loop = false) do
          @agent = RightScale::Agent.new(:user => "me", :identity => @identity)
          @agent.run
          @agent.terminate
        end
      end

      it "should terminate immediately if called a second time but should still execute block" do
        @mapper_proxy.should_receive(:pending_requests).and_return(["request"]).once
        @mapper_proxy.should_receive(:request_age).and_return(10).once
        @dispatcher.should_receive(:dispatch_age).and_return(10).once
        flexmock(EM::Timer).should_receive(:new).with(20, Proc).and_return(@timer).once
        @timer.should_receive(:cancel).once
        run_in_em do
          @agent = RightScale::Agent.new(:user => "me", :identity => @identity)
          @agent.run
          called = 0
          @agent.terminate { called += 1 }
          called.should == 0
          @agent.terminate { called += 1 }
          called.should == 1
        end
      end

    end

  end

end
